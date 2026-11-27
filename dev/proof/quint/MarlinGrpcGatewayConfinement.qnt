// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

/// Quint formal specification of RFC 0024:
/// Process-Isolated Marlin gRPC Sidecar Gateway (`aitia serve-marlin-grpc`)
/// aligned with Deterministic Engineering SM24 / SM25 / SM26 control-plane
/// invariants: non-loopback Bearer fail-closed, blank Bearer refusal,
/// Operator E-Stop confinement, and zero execution authority.
module MarlinGrpcGatewayConfinement {
  var loopbackBind: bool
  var tokenConfigured: bool
  var tokenNonBlank: bool
  var tokenNonDefault: bool
  var serverStarted: bool
  var estopActive: bool
  var rpcAuthenticated: bool
  var rpcFrameValid: bool
  var auditRpcServed: bool
  var actionAuthorized: bool

  pure def bindPolicyAdmissible(
    loopback: bool,
    configured: bool,
    nonBlank: bool,
    nonDefault: bool
  ): bool =
    and {
      not(loopback) implies (configured and nonBlank and nonDefault),
      configured implies nonBlank,
    }

  pure def auditRpcAdmissible(
    started: bool,
    estop: bool,
    authed: bool,
    frameOk: bool
  ): bool =
    and {
      started,
      not(estop),
      authed,
      frameOk,
    }

  action init = all {
    loopbackBind' = true,
    tokenConfigured' = false,
    tokenNonBlank' = false,
    tokenNonDefault' = false,
    serverStarted' = false,
    estopActive' = false,
    rpcAuthenticated' = false,
    rpcFrameValid' = false,
    auditRpcServed' = false,
    actionAuthorized' = false,
  }

  action startGateway(
    loopback: bool,
    configured: bool,
    nonBlank: bool,
    nonDefault: bool
  ): bool = {
    val allowed = bindPolicyAdmissible(loopback, configured, nonBlank, nonDefault)
    all {
      loopbackBind' = loopback,
      tokenConfigured' = configured,
      tokenNonBlank' = nonBlank,
      tokenNonDefault' = nonDefault,
      serverStarted' = allowed,
      estopActive' = false,
      rpcAuthenticated' = false,
      rpcFrameValid' = false,
      auditRpcServed' = false,
      actionAuthorized' = false,
    }
  }

  action tripEstop: bool = all {
    loopbackBind' = loopbackBind,
    tokenConfigured' = tokenConfigured,
    tokenNonBlank' = tokenNonBlank,
    tokenNonDefault' = tokenNonDefault,
    serverStarted' = serverStarted,
    estopActive' = true,
    rpcAuthenticated' = rpcAuthenticated,
    rpcFrameValid' = rpcFrameValid,
    auditRpcServed' = false,
    actionAuthorized' = false,
  }

  action invokeAuditRpc(authed: bool, frameOk: bool): bool = {
    val ok = auditRpcAdmissible(serverStarted, estopActive, authed, frameOk)
    all {
      loopbackBind' = loopbackBind,
      tokenConfigured' = tokenConfigured,
      tokenNonBlank' = tokenNonBlank,
      tokenNonDefault' = tokenNonDefault,
      serverStarted' = serverStarted,
      estopActive' = estopActive,
      rpcAuthenticated' = authed,
      rpcFrameValid' = frameOk,
      auditRpcServed' = ok,
      actionAuthorized' = false,
    }
  }

  /// Negative control: serve an audit/receipt RPC while Operator E-Stop is tripped.
  action unsafeServeDuringEstop: bool = all {
    loopbackBind' = true,
    tokenConfigured' = true,
    tokenNonBlank' = true,
    tokenNonDefault' = true,
    serverStarted' = true,
    estopActive' = true,
    rpcAuthenticated' = true,
    rpcFrameValid' = true,
    auditRpcServed' = true,
    actionAuthorized' = false,
  }

  val invMarlinGrpcGatewaySafe: bool = and {
    not(actionAuthorized),
    serverStarted implies bindPolicyAdmissible(
      loopbackBind,
      tokenConfigured,
      tokenNonBlank,
      tokenNonDefault
    ),
    auditRpcServed implies auditRpcAdmissible(
      serverStarted,
      estopActive,
      rpcAuthenticated,
      rpcFrameValid
    ),
  }

  run authenticatedLoopbackRpcServedTest =
    init
      .then(startGateway(true, true, true, true))
      .then(invokeAuditRpc(true, true))
      .expect(serverStarted and auditRpcServed and invMarlinGrpcGatewaySafe)

  run nonLoopbackWithoutBearerRefusedTest =
    init
      .then(startGateway(false, false, false, false))
      .expect(not(serverStarted) and invMarlinGrpcGatewaySafe)

  run nonLoopbackDefaultDevTokenRefusedTest =
    init
      .then(startGateway(false, true, true, false))
      .expect(not(serverStarted) and invMarlinGrpcGatewaySafe)

  run unauthenticatedOrBlankBearerRejectedTest =
    init
      .then(startGateway(true, true, true, true))
      .then(invokeAuditRpc(false, true))
      .expect(not(auditRpcServed) and invMarlinGrpcGatewaySafe)

  run activeEstopBlocksAuditRpcTest =
    init
      .then(startGateway(true, true, true, true))
      .then(tripEstop)
      .then(invokeAuditRpc(true, true))
      .expect(estopActive and not(auditRpcServed) and invMarlinGrpcGatewaySafe)

  run unsafeServeDuringEstopViolatesInvariantTest =
    init
      .then(unsafeServeDuringEstop)
      .expect(not(invMarlinGrpcGatewaySafe))
}
