// Runtime controller for the open-mascot engine, adapted from open-mascot's
// web.js with the DOM renderer and requestAnimationFrame loop removed.
// The host (QML) owns the frame loop: it calls sample(timestamp) each frame
// and can stop ticking whenever isAnimating(timestamp) returns false.
import { hasExpressionMotion, interpolatePose, sampleAnimation, sampleExpression } from './motion.mjs'
import { buildScene } from './scene.mjs'
import { buildMouth } from './mouth.mjs'

const clamp1 = value => Math.max(-1, Math.min(1, Number.isFinite(value) ? value : 0))

export const createController = (definition, options = {}) => {
  let animationKey = options.animation ?? Object.keys(definition.animations)[0]
  if (!definition.animations[animationKey]) animationKey = Object.keys(definition.animations)[0]
  let staticExpression = null
  let playing = true
  let elapsedBeforeStart = 0
  let startedAt = options.now ?? Date.now()
  let bridge = null
  let latestSample = null
  let onceCompleted = false
  const reducedMotion = options.reducedMotion ?? false
  const lookGain = Number.isFinite(options.lookGain) ? options.lookGain : 1

  let lookTarget = { x: 0, y: 0 }
  let lookEyes = { x: 0, y: 0 }
  let lookBody = { x: 0, y: 0 }
  let lookFollowing = false
  let lookActive = false
  let lookRemaining = 0
  let lastLookFrame = startedAt

  const applyLookTarget = (sourcePose, timestamp) => {
    const delta = Math.max(0, Math.min(64, timestamp - lastLookFrame))
    lastLookFrame = timestamp
    const eyeAmount = 1 - Math.exp(-delta / 72)
    const bodyAmount = 1 - Math.exp(-delta / 190)
    lookEyes.x += (lookTarget.x - lookEyes.x) * eyeAmount
    lookEyes.y += (lookTarget.y - lookEyes.y) * eyeAmount
    lookBody.x += (lookTarget.x - lookBody.x) * bodyAmount
    lookBody.y += (lookTarget.y - lookBody.y) * bodyAmount
    const remaining = Math.max(
      Math.abs(lookEyes.x - lookTarget.x),
      Math.abs(lookEyes.y - lookTarget.y),
      Math.abs(lookBody.x - lookTarget.x),
      Math.abs(lookBody.y - lookTarget.y),
    )
    lookRemaining = remaining
    lookActive = lookFollowing || remaining > 0.002
    const pose = JSON.parse(JSON.stringify(sourcePose))
    pose.gaze.x += lookEyes.x * 12 * lookGain
    pose.gaze.y += lookEyes.y * 9 * lookGain
    pose.blob.yaw += lookBody.x * 15 * lookGain
    pose.blob.pitch -= lookBody.y * 10 * lookGain
    pose.blob.roll += lookBody.x * lookBody.y * 2.2 * lookGain
    return pose
  }

  const samplePose = timestamp => {
    const elapsedMs = playing ? elapsedBeforeStart + timestamp - startedAt : elapsedBeforeStart
    const expressionElapsedMs = staticExpression ? Math.max(0, timestamp - startedAt) : elapsedMs
    const sampled = staticExpression
      ? {
          pose: sampleExpression(definition, staticExpression, expressionElapsedMs, { reducedMotion }),
          done: true,
        }
      : sampleAnimation(definition, animationKey, elapsedMs, { reducedMotion })
    let pose = sampled.pose
    if (bridge) {
      const progress = bridge.durationMs ? (timestamp - bridge.startedAt) / bridge.durationMs : 1
      if (progress < 1) pose = interpolatePose(bridge.from, pose, progress, 'gentle')
      else bridge = null
    }
    // Keep the pre-look pose: bridges must start from it, or the look offset
    // gets baked into `from` AND re-applied on top each frame — a visible
    // gaze jerk toward the look side at every animation switch.
    const basePose = pose
    pose = applyLookTarget(pose, timestamp)
    if (!staticExpression && sampled.done && definition.animations[animationKey].playback === 'once' && playing) {
      playing = false
      elapsedBeforeStart = sampled.duration
      onceCompleted = true
    }
    latestSample = { sampled, pose, basePose, elapsedMs }
    return pose
  }

  // Looping animations whose steps carry fast expression motion (boing,
  // tremble, darting eyes) need the busy frame rate too, not just held expressions —
  // a bounce sampled at the idle rate stutters.
  const animationHasFastMotion = animation => {
    if (!animation || !Array.isArray(animation.steps)) return false
    return animation.steps.some(step => {
      const expression = definition.expressions[step.expression]
      const m = expression && expression.motion
      return Boolean(m && (m.body === 'boing' || m.body === 'tremble' || m.eyes === 'tremble' || m.eyes === 'micro-saccades'))
    })
  }

  const startBridge = (fromPose, timestamp, durationMs) => {
    bridge = reducedMotion ? null : { from: fromPose, startedAt: timestamp, durationMs }
  }

  let mouthEnabled = options.mouthEnabled !== false
  let mouthShown = null
  let mouthGrow = 0
  let mouthLastTs = startedAt

  const sameMouth = (a, b) =>
    (!a && !b) || Boolean(a && b && a.mode === b.mode && a.scale === b.scale)

  // The active animation or held expression can carry a mouth. The global
  // toggle hides optional mouths; sources marked mouthRequired (the dedicated
  // speaking/smiling/frowning animations) always show theirs.
  const mouthFor = () => {
    const source = staticExpression
      ? definition.expressions[staticExpression]
      : definition.animations[animationKey]
    if (!source || !source.mouth) return null
    if (!mouthEnabled && !source.mouthRequired) return null
    return {
      mode: source.mouth,
      scale: Number.isFinite(source.mouthScale) ? source.mouthScale : 1,
    }
  }

  return {
    sample(timestamp) {
      const pose = samplePose(timestamp)
      const scene = buildScene(definition, pose)
      // Mouth shape changes shrink out and grow back in (~160ms each way)
      // instead of popping between outlines when the animation switches.
      const target = mouthFor()
      const dt = Math.max(0, Math.min(64, timestamp - mouthLastTs))
      mouthLastTs = timestamp
      const step = dt / 160
      if (sameMouth(target, mouthShown)) {
        if (mouthShown) mouthGrow = Math.min(1, mouthGrow + step)
      } else if (mouthShown && mouthGrow > 0) {
        mouthGrow = Math.max(0, mouthGrow - step)
      } else {
        mouthShown = target ? { mode: target.mode, scale: target.scale } : null
        mouthGrow = 0
      }
      if (mouthShown && mouthGrow > 0.03) {
        const eased = mouthGrow * mouthGrow * (3 - 2 * mouthGrow)
        scene.mouth = buildMouth(definition, pose, latestSample.elapsedMs, mouthShown.mode, mouthShown.scale, eased)
      }
      return scene
    },
    setMouthEnabled(on) {
      mouthEnabled = Boolean(on)
    },
    getMouthEnabled() {
      return mouthEnabled
    },
    play(nextAnimation, timestamp = Date.now()) {
      if (!definition.animations[nextAnimation]) throw new Error(`Unknown animation: ${nextAnimation}`)
      samplePose(timestamp)
      const from = latestSample.basePose
      animationKey = nextAnimation
      staticExpression = null
      elapsedBeforeStart = 0
      startedAt = timestamp
      playing = true
      onceCompleted = false
      startBridge(from, timestamp, 540)
    },
    setExpression(expressionKey, timestamp = Date.now()) {
      if (!definition.expressions[expressionKey]) throw new Error(`Unknown expression: ${expressionKey}`)
      samplePose(timestamp)
      const from = latestSample.basePose
      staticExpression = expressionKey
      playing = false
      elapsedBeforeStart = 0
      startedAt = timestamp
      onceCompleted = false
      startBridge(from, timestamp, 460)
    },
    pause(timestamp = Date.now()) {
      if (!playing) return
      elapsedBeforeStart += timestamp - startedAt
      playing = false
    },
    resume(timestamp = Date.now()) {
      if (playing || staticExpression) return
      startedAt = timestamp
      playing = true
      onceCompleted = false
    },
    setDefinition(nextDefinition, timestamp = Date.now()) {
      samplePose(timestamp)
      const from = latestSample.basePose
      definition = nextDefinition
      if (!definition.animations[animationKey]) animationKey = Object.keys(definition.animations)[0]
      if (staticExpression && !definition.expressions[staticExpression]) staticExpression = null
      elapsedBeforeStart = 0
      startedAt = timestamp
      if (!staticExpression) playing = true
      startBridge(from, timestamp, 420)
    },
    setLookTarget(x, y) {
      lookTarget = { x: clamp1(x), y: clamp1(y) }
      lookFollowing = true
      lookActive = true
    },
    clearLookTarget() {
      lookTarget = { x: 0, y: 0 }
      lookFollowing = false
      lookActive = true
    },
    // True while something fast is happening (a transition bridge, the gaze
    // still converging, an expression with its own motion, or a one-shot
    // animation). The host renders at full fps while busy and can drop to a
    // low idle rate otherwise — ambient breathing survives low fps fine.
    isBusy() {
      const expressionMoving = !reducedMotion
        && staticExpression
        && hasExpressionMotion(definition.expressions[staticExpression])
      const oncePlaying = !staticExpression && playing
        && definition.animations[animationKey]
        && definition.animations[animationKey].playback === 'once'
      const loopMoving = !reducedMotion && !staticExpression && playing
        && animationHasFastMotion(definition.animations[animationKey])
      const mouth = mouthFor()
      const mouthMoving = !sameMouth(mouth, mouthShown) || (mouthShown && mouthGrow < 1)
      return Boolean(bridge || lookRemaining > 0.002 || expressionMoving || oncePlaying || loopMoving
        || mouthMoving || (playing && mouth && mouth.mode === 'flap'))
    },
    // True while the host must keep ticking frames.
    isAnimating() {
      const expressionMoving = !reducedMotion
        && staticExpression
        && hasExpressionMotion(definition.expressions[staticExpression])
      const mouthMoving = !sameMouth(mouthFor(), mouthShown) || (mouthShown && mouthGrow < 1)
      return Boolean(playing || bridge || lookActive || expressionMoving || mouthMoving)
    },
    consumeOnceCompleted() {
      const value = onceCompleted
      onceCompleted = false
      return value
    },
    getState() {
      return {
        animation: animationKey,
        expression: staticExpression,
        playing,
        elapsedMs: latestSample ? latestSample.elapsedMs : 0,
        lookTarget,
        lookFollowing,
      }
    },
    getDefinition() {
      return definition
    },
  }
}
