// The dark "room" backdrop with the draggable lamp pull-string. Ported from the
// original mockup (App.jsx). Pulling the brass handle down toggles the light;
// the routed auth form renders inside the glass card as {children}.

import { useState, useEffect } from 'react';
import { useLocation } from 'react-router-dom';
import { motion, useMotionValue, useTransform } from 'framer-motion';

export default function RoomScene({ children }) {
  const loc = useLocation();
  // The lamp starts off (pull-to-reveal), except on the password-reset flow where
  // it turns on by default so the form is visible immediately.
  const wantsOn = loc.pathname === '/forgot' || loc.pathname === '/reset';
  const [isOn, setIsOn] = useState(wantsOn);
  useEffect(() => {
    if (wantsOn) setIsOn(true);
  }, [wantsOn]);

  const x = useMotionValue(0);
  const y = useMotionValue(0);

  const d = useTransform([x, y], ([latestX, latestY]) => {
    return `M 0 0 L ${latestX} ${80 + latestY}`;
  });

  const handleDragEnd = (event, info) => {
    if (info.offset.y > 30) setIsOn((prev) => !prev);
  };

  return (
    <div className={`room ${isOn ? 'on' : 'off'}`}>
      <div className="hint-text">Pull the string to toggle the light</div>

      <div className="lamp-container">
        <div className="lamp-glow"></div>
        <div className="lamp-head"></div>
        <div className="light-beam"></div>
        <div className="lamp-stem"></div>
        <div className="lamp-base"></div>
        <div className="desk-surface"></div>

        <svg
          style={{
            position: 'absolute',
            top: 12,
            left: '50%',
            marginLeft: 55,
            width: 2,
            height: 2,
            overflow: 'visible',
            zIndex: 5,
            pointerEvents: 'none',
          }}
        >
          <motion.path d={d} stroke="#222" strokeWidth="2" strokeLinecap="round" />
        </svg>

        <motion.div
          className="string-handle"
          style={{
            position: 'absolute',
            top: 92,
            left: '50%',
            marginLeft: 49,
            x,
            y,
            cursor: 'grab',
            zIndex: 6,
          }}
          drag
          dragConstraints={{ top: 0, bottom: 0, left: 0, right: 0 }}
          dragElastic={{ top: 0, bottom: 0.6, left: 0.3, right: 0.3 }}
          dragTransition={{ bounceStiffness: 300, bounceDamping: 4 }}
          onDragEnd={handleDragEnd}
          whileTap={{ cursor: 'grabbing' }}
        />
      </div>

      {isOn && (
        <motion.div
          className="login-form-container"
          initial={{ opacity: 0, filter: 'blur(10px)' }}
          animate={{ opacity: 1, filter: 'blur(0px)' }}
          transition={{ duration: 0.4, ease: 'easeOut' }}
        >
          {children}
        </motion.div>
      )}
    </div>
  );
}
