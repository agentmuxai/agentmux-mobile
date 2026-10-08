/// The MuxBus relay this build talks to. `--dart-define=MUXBUS_API_BASE=...`
/// points a build at another relay (staging, a local one).
const muxbusApiBase = String.fromEnvironment(
  'MUXBUS_API_BASE',
  defaultValue: 'https://muxbus.agentmux.ai',
);
