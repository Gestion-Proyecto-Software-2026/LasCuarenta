const nodemailer = require("nodemailer");

let transporter;

function getTransporter() {
  if (!transporter) {
    transporter = nodemailer.createTransport({
      host: process.env.SMTP_HOST,
      port: Number(process.env.SMTP_PORT || 587),
      secure: process.env.SMTP_SECURE === "true",
      auth: process.env.SMTP_USER
        ? { user: process.env.SMTP_USER, pass: process.env.SMTP_PASS }
        : undefined,
    });
  }
  return transporter;
}

async function enviarCorreo({ to, subject, text }) {
  await getTransporter().sendMail({
    from: process.env.SMTP_FROM || "no-reply@cartas-online.local",
    to,
    subject,
    text,
  });
}

module.exports = { enviarCorreo };
