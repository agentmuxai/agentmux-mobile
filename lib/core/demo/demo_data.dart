// Static sample data for demo mode (see docs/specs/APP_STORE_SUBMISSION_READINESS.md).
//
// This exists so anyone opening the app without a LAN AgentMux instance or a
// real Cognito account — most notably an App Store reviewer — can still see
// what the agent list, message feed, and statuses actually look like. Timestamps
// are computed relative to `DateTime.now()` at call time (not baked into fixed
// ISO strings) so the "Active now" / "Xm ago" labels always look plausible no
// matter when the screen is opened. No network call is ever made on this path.
import '../models/agent.dart';
import '../models/message.dart';

List<Agent> buildDemoAgents() {
  final now = DateTime.now().toUtc();
  return [
    Agent(
      id: 'Nova',
      lastSeen: now.subtract(const Duration(seconds: 20)).toIso8601String(),
      messagesSent: 128,
    ),
    Agent(
      id: 'Piper',
      lastSeen: now.subtract(const Duration(minutes: 12)).toIso8601String(),
      messagesSent: 42,
    ),
    Agent(
      id: 'Scout',
      lastSeen: now.subtract(const Duration(minutes: 3)).toIso8601String(),
      messagesSent: 7,
    ),
    Agent(
      id: 'Relay',
      lastSeen: now.subtract(const Duration(hours: 6)).toIso8601String(),
      messagesSent: 301,
    ),
  ];
}

List<Message> buildDemoMessages(String agentId) {
  final now = DateTime.now().toUtc();
  Message m(int minutesAgo, String from, String to, String text,
      {String priority = 'normal'}) {
    return Message(
      id: '$agentId-$minutesAgo',
      fromAgent: from,
      toAgent: to,
      message: text,
      priority: priority,
      timestamp: now.subtract(Duration(minutes: minutesAgo)).toIso8601String(),
      read: minutesAgo > 5,
    );
  }

  return switch (agentId) {
    'Nova' => [
        m(1, 'Nova', 'you', 'Build is green — deploy preview is up.'),
        m(18, 'you', 'Nova', 'Can you re-run the flaky integration test?'),
        m(45, 'Nova', 'you', 'Found the root cause, opening a PR now.',
            priority: 'high'),
      ],
    'Piper' => [
        m(12, 'Piper', 'you', 'Docs draft ready for review.'),
        m(90, 'you', 'Piper', 'Ping me when the API reference section is done.'),
      ],
    'Scout' => [
        m(3, 'Scout', 'you', 'Crawled 240 pages, 3 broken links found.',
            priority: 'urgent'),
        m(20, 'you', 'Scout', 'Start the weekly link-check sweep.'),
      ],
    _ => [
        m(360, 'Relay', 'you', 'Nightly sync finished, no conflicts.'),
        m(420, 'you', 'Relay', 'Kick off the nightly sync a bit earlier today.'),
      ],
  };
}
