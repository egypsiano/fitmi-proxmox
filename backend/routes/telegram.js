const express = require('express');
const router = express.Router();
const fs = require('fs');
const path = require('path');

const uploadDir = "/mnt/uploads";

router.post('/message', async (req, res) => {
  const { chat_id, text } = req.body;

  if (!chat_id || !text) {
    return res.status(400).json({ error: "Missing chat ID or message." });
  }

  if (text.startsWith("/list")) {
    fs.readdir(uploadDir, (err, files) => {
      if (err) return res.status(500).json({ error: "Could not list files." });

      const fileList = files.join("\n");
      sendTelegramMessage(chat_id, "📁 Uploaded Files:\n" + fileList);
      res.json({ status: "success" });
    });
  } else if (text.startsWith("/delete ")) {
    const filename = text.replace("/delete ", "");
    const filePath = path.join(uploadDir, filename);

    fs.unlink(filePath, (err) => {
      if (err) {
        sendTelegramMessage(chat_id, "❌ Could not delete file: " + filename);
      } else {
        sendTelegramMessage(chat_id, "🗑️ Deleted file: " + filename);
      }
      res.json({ status: "success" });
    });
  } else {
    sendTelegramMessage(chat_id, "ℹ️ Unknown command.");
    res.json({ status: "success" });
  }
});

function sendTelegramMessage(chatId, message) {
  const { Telegraf } = require('telegraf');
  const bot = new Telegraf(process.env.TELEGRAM_BOT_TOKEN);

  bot.telegram.sendMessage(chatId, message)
    .catch(err => console.error("Telegram error:", err.message));
}

module.exports = router;