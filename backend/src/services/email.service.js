// Email service (nodemailer) — currently only used for password resets.
// If SMTP is not configured the reset URL is logged to the console instead so
// local development works without a mail server.

import nodemailer from 'nodemailer';

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
  });
  return transporter;
};

/**
 * Send a password reset email carrying BOTH a 6-digit code (for in-app entry)
 * and a one-time link (for the web flow). Either resets the password.
 * @param {string} to recipient email
 * @param {{ otp: string, resetUrl: string }} opts
 */
export const sendPasswordResetEmail = async (to, { otp, resetUrl }) => {
  const t = getTransporter();

  if (!t) {
    // Dev fallback — surface both so the flow can be tested without SMTP.
    console.log(
      `[email disabled] Password reset for ${to}: code=${otp}  link=${resetUrl}`
    );
    return;
  }

  await t.sendMail({
    from: process.env.EMAIL_FROM || 'CypherFy <noreply@cypherfy.in>',
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
  });
};

/**
 * Send a 6-digit email-verification code to a newly registered user. Falls back
 * to a console log when SMTP isn't configured, so the flow works locally.
 * @param {string} to recipient email
 * @param {{ otp: string }} opts
 */
export const sendVerificationEmail = async (to, { otp }) => {
  const t = getTransporter();

  if (!t) {
    console.log(`[email disabled] Verification code for ${to}: ${otp}`);
    return;
  }

  await t.sendMail({
    from: process.env.EMAIL_FROM || 'CypherFy <noreply@cypherfy.in>',
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
  });
};
