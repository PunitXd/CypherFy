// Email service — password resets and signup verification codes.
//
// Delivery backend, in priority order:
//   1. RESEND_API_KEY  → Resend's HTTPS API (port 443).
//   2. SMTP_*          → nodemailer, for self-hosted/local mail servers.
//   3. neither         → log the code to the console so local dev works.
//
// The HTTPS API is preferred because many hosts (Render's free tier among them)
// block outbound SMTP ports 25/465/587 outright. A blocked port doesn't fail
// fast — the connection is dropped silently and sendMail hangs until the client
// gives up. Since callers await these functions inside a request handler, that
// stalls signup entirely. Port 443 is never blocked, and every path below is
// bounded by a timeout so a mail outage degrades to a clear error, not a hang.

import nodemailer from 'nodemailer';

// Bound on every delivery attempt. Comfortably above normal latency (~1s) while
// still failing well inside a typical client timeout.
const SEND_TIMEOUT_MS = 10_000;

const FROM = () => process.env.EMAIL_FROM || 'CypherFy <noreply@cypherfy.in>';

let transporter = null;

const getTransporter = () => {
  if (transporter) return transporter;

  const { SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASS } = process.env;
  if (!SMTP_HOST || !SMTP_USER || !SMTP_PASS) return null;

  transporter = nodemailer.createTransport({
    host: SMTP_HOST,
    port: Number(SMTP_PORT) || 587,
    secure: Number(SMTP_PORT) === 465, // true for 465, false for 587/STARTTLS
    auth: { user: SMTP_USER, pass: SMTP_PASS },
    // Without these nodemailer waits indefinitely on a silently dropped
    // connection — the exact failure mode of a blocked SMTP port.
    connectionTimeout: SEND_TIMEOUT_MS,
    greetingTimeout: SEND_TIMEOUT_MS,
    socketTimeout: SEND_TIMEOUT_MS,
  });
  return transporter;
};

/**
 * Send one message via Resend's HTTPS API.
 * @throws {Error} on a non-2xx response, with the API's message when present.
 */
const sendViaResend = async ({ to, subject, text, html }) => {
  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${process.env.RESEND_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ from: FROM(), to, subject, text, html }),
    signal: AbortSignal.timeout(SEND_TIMEOUT_MS),
  });

  if (!res.ok) {
    // Resend returns { message, name } on failure; fall back to the status text
    // if the body isn't JSON (proxy error pages, etc.).
    const detail = await res
      .json()
      .then((b) => b?.message || JSON.stringify(b))
      .catch(() => res.statusText);
    throw new Error(`Resend API ${res.status}: ${detail}`);
  }
};

/**
 * Deliver a message through whichever backend is configured, or log it when
 * none is. `logLine` is what the console fallback prints — it must carry the
 * code/link so the flow stays testable without a mail provider.
 * @param {{to:string, subject:string, text:string, html:string, logLine:string}} msg
 */
const deliver = async ({ to, subject, text, html, logLine }) => {
  if (process.env.RESEND_API_KEY) {
    await sendViaResend({ to, subject, text, html });
    return;
  }

  const t = getTransporter();
  if (t) {
    await t.sendMail({ from: FROM(), to, subject, text, html });
    return;
  }

  console.log(logLine);
};

/**
 * Send a password reset email carrying BOTH a 6-digit code (for in-app entry)
 * and a one-time link (for the web flow). Either resets the password.
 * @param {string} to recipient email
 * @param {{ otp: string, resetUrl: string }} opts
 */
export const sendPasswordResetEmail = async (to, { otp, resetUrl }) =>
  deliver({
    to,
    subject: 'Reset your CypherFy password',
    text:
      `Your CypherFy password reset code is: ${otp}\n\n` +
      `Enter it in the app, or reset on the web using this link:\n${resetUrl}\n\n` +
      `This code and link are valid for 15 minutes. ` +
      `If you didn't request this, you can ignore this email.`,
    html: `<p>Your CypherFy password reset code is:</p>
           <p style="font-size:28px;font-weight:bold;letter-spacing:6px;margin:12px 0">${otp}</p>
           <p>Enter it in the app, or <a href="${resetUrl}">reset on the web</a> instead.</p>
           <p style="color:#888;font-size:13px">This code and link are valid for 15 minutes. If you didn't request this, you can safely ignore this email.</p>`,
    logLine: `[email disabled] Password reset for ${to}: code=${otp}  link=${resetUrl}`,
  });

/**
 * Send a 6-digit email-verification code to a newly registered user.
 * @param {string} to recipient email
 * @param {{ otp: string }} opts
 */
export const sendVerificationEmail = async (to, { otp }) =>
  deliver({
    to,
    subject: 'Your CypherFy verification code',
    text:
      `Welcome to CypherFy!\n\n` +
      `Your verification code is: ${otp}\n\n` +
      `Enter it in the app to finish creating your account. ` +
      `This code is valid for 15 minutes. ` +
      `If you didn't sign up, you can ignore this email.`,
    html: `<p>Welcome to CypherFy!</p>
           <p>Your verification code is:</p>
           <p style="font-size:28px;font-weight:bold;letter-spacing:6px;margin:12px 0">${otp}</p>
           <p>Enter it in the app to finish creating your account.</p>
           <p style="color:#888;font-size:13px">This code is valid for 15 minutes. If you didn't sign up, you can safely ignore this email.</p>`,
    logLine: `[email disabled] Verification code for ${to}: ${otp}`,
  });
