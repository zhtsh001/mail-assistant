// Only explicit UI actions reach this script. Model output never selects a target.
function handleRequest(Mail, request) {
  if (!request || !["open", "draft"].includes(request.action) ||
      typeof request.id !== "string" || !request.id) {
    throw new Error("无效的邮件操作。");
  }
  if (request.action === "draft" &&
      (typeof request.body !== "string" || !request.body.trim() || request.body.length > 100000)) {
    throw new Error("回复正文为空或过长。");
  }
  // Look up read and unread inbox messages; never guess by subject or sender.
  const matches = Mail.inbox.messages.whose({ messageId: request.id })();
  const exact = matches.filter(message =>
    String(message.messageId()) === request.id &&
    (!request.localID || String(message.id()) === request.localID));
  if (exact.length !== 1) {
    throw new Error("无法唯一定位原邮件，可能已移动或删除。请重新整理后再试。");
  }
  if (request.action === "open") {
    Mail.open(exact[0]);
    Mail.activate();
    return "已在 Mail 中打开原邮件。";
  }
  // Mail chooses the reply account, Reply-To address and threading headers.
  const reply = Mail.reply(exact[0], { openingWindow: false, replyToAll: false });
  reply.content = request.body;
  Mail.save(reply);
  reply.visible = true;
  Mail.activate();
  return "回复草稿已保存并在 Mail 中打开；尚未发送。";
}

function run(argv) {
  ObjC.import("Foundation");
  const text = $.NSString.stringWithContentsOfFileEncodingError(argv[0], $.NSUTF8StringEncoding, null);
  if (!text) throw new Error("无法读取邮件操作请求。");
  return handleRequest(Application("Mail"), JSON.parse(ObjC.unwrap(text)));
}
