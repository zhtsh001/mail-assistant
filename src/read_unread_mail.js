function clean(value) {
  if (value === null || value === undefined) return "";
  return String(value).replace(/\s+/g, " ").trim();
}

function safe(callable, fallback) {
  try {
    const value = callable();
    return value === null || value === undefined ? fallback : value;
  } catch (_) {
    return fallback;
  }
}

function headerValue(source, name) {
  if (!source) return "";
  const headerBlock = String(source).split(/\r?\n\r?\n/, 1)[0].slice(0, 131072);
  const unfolded = headerBlock.replace(/\r?\n[ \t]+/g, " ");
  const match = unfolded.match(new RegExp(`^${name}:\\s*(.+)$`, "im"));
  return match ? clean(match[1]) : "";
}

function httpUrls(value) {
  const matches = String(value || "").match(/https?:\/\/[^>\s,]+/gi) || [];
  return [...new Set(matches)].slice(0, 5);
}

function run(argv) {
  const Mail = Application("Mail");
  const args = Array.isArray(argv) ? argv : [];
  let sinceHours = 72;
  let maxMessages = 200;

  for (const arg of args) {
    if (arg.indexOf("--since-hours=") === 0) {
      sinceHours = Math.max(1, Number(arg.split("=")[1]) || 72);
    } else if (arg.indexOf("--max=") === 0) {
      maxMessages = Math.max(1, Math.min(500, Number(arg.split("=")[1]) || 200));
    }
  }

  const cutoff = Date.now() - sinceHours * 60 * 60 * 1000;
  const unread = safe(
    () => Mail.inbox.messages.whose({ readStatus: false })(),
    []
  );

  const messages = [];
  for (const message of unread) {
    const received = safe(() => message.dateReceived(), null);
    const receivedMs = received instanceof Date ? received.getTime() : 0;
    if (receivedMs && receivedMs < cutoff) continue;

    const mailbox = safe(() => message.mailbox(), null);
    const content = clean(safe(() => message.content(), ""));
    const source = safe(() => message.source(), "");
    const listUnsubscribe = headerValue(source, "List-Unsubscribe");
    messages.push({
      id: clean(safe(() => message.messageId(), "")) || clean(safe(() => message.id(), "")),
      sender: clean(safe(() => message.sender(), "")),
      subject: clean(safe(() => message.subject(), "(无主题)")),
      receivedAt: received instanceof Date ? received.toISOString() : "",
      mailbox: mailbox ? clean(safe(() => mailbox.name(), "")) : "",
      localID: clean(safe(() => message.id(), "")),
      replyTo: clean(safe(() => message.replyTo(), "")),
      snippet: content.slice(0, 6000),
      unsubscribeUrls: httpUrls(listUnsubscribe)
    });
  }

  messages.sort((a, b) => b.receivedAt.localeCompare(a.receivedAt));
  return JSON.stringify({
    generatedAt: new Date().toISOString(),
    sinceHours,
    count: Math.min(messages.length, maxMessages),
    messages: messages.slice(0, maxMessages)
  });
}
