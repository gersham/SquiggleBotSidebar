// squigglebot extension: the stock mascot definition, in one place.
//
// Builds an open-mascot definition from squigglebot's options (shape, colors,
// eye geometry) and dresses it with the mouth set — the dedicated speaking/
// smiling/frowning loops plus a fitting default mouth for every stock face.
//
// shell.qml currently carries its own copy of this wiring in
// buildDefinition()/addMouthAnimations(); it should migrate to this module so
// the desktop mascot and the bar widget (Widget.qml) stay one definition.

import { createDefinition, createPose } from './definition.mjs'
import { hasBlobShape } from './shapes.mjs'

export function buildMascotDefinition(options = {}) {
  const shape = hasBlobShape(options.shape) ? options.shape : 'round'
  const def = createDefinition({
    name: options.name || 'squigglebot',
    shape,
    renderMode: options.renderMode || 'projected-3d',
    color: options.color || '#d3a62a',
    eyeColor: options.eyeColor || '#181a1c',
  })
  const eyes = options.eyes
  if (eyes) {
    if (eyes.shape) def.face.eyeShape = eyes.shape
    if (Number.isFinite(eyes.width)) def.face.eyeWidth = eyes.width
    if (Number.isFinite(eyes.height)) def.face.eyeHeight = eyes.height
    if (Number.isFinite(eyes.gap)) def.face.eyeGap = eyes.gap
    if (Number.isFinite(eyes.y)) def.face.eyeY = eyes.y
  }
  addExpressiveSet(def)
  addMouthAnimations(def)
  return def
}

const eye = (scaleX = 1, scaleY = 1, x = 0, y = 0, rotation = 0) => ({ scaleX, scaleY, x, y, rotation })
const motion = (body = 'none', eyes = 'none') => ({ body, eyes })

// squigglebot's body language, layered over the stock open-mascot faces.
//
// Squash is the star: positive squash compresses him (and, via scene.mjs's
// volume-preserving bulge, widens him), negative stretches him tall and thin.
// Lift is viewbox pixels downward, so a hop is negative lift. Poses stay
// inside the widget's hug region (Widget.qml hugPadX/hugPadY) — lifts within
// about ±30 and squash within [-0.14, 0.26].
//
// Adds: squash/stretch beats for hops and startles, fidget one-shots (glance,
// tilt, peek, yawn, wiggle, stretch, look-around, hop, bounce), idle variants
// (idle-perky, idle-drowsy), and a real sleep cycle: `dozing` nods off,
// `sleeping` breathes with closed eyes, `waking` stretches back up. Stock
// idle/happy/surprised/victory-bounce/sleeping are replaced with bouncier
// squigglebot versions.
export function addExpressiveSet(def) {
  const expressions = {
    // --- squash & stretch beats
    squished: { label: 'Squished', pose: createPose({ squash: 0.24, lift: 26, gazeY: 2, leftEye: eye(1.18, 0.7, 0, 1), rightEye: eye(1.18, 0.7, 0, 1) }) },
    landing: { label: 'Landing', pose: createPose({ squash: 0.15, lift: 16, gazeY: 1, leftEye: eye(1.1, 0.86), rightEye: eye(1.1, 0.86) }) },
    stretched: { label: 'Stretched', pose: createPose({ squash: -0.12, lift: -26, gazeY: -3, leftEye: eye(0.9, 1.22, 0, -1), rightEye: eye(0.9, 1.22, 0, -1) }) },
    'hop-mini': { label: 'Mini hop', pose: createPose({ squash: -0.07, lift: -15, gazeY: -2, leftEye: eye(0.95, 1.12), rightEye: eye(0.95, 1.12) }) },
    startled: { label: 'Startled', pose: createPose({ pitch: -2, yaw: -6, roll: -3, squash: -0.1, lift: -14, leftEye: eye(1.5, 0.8, 0, -1), rightEye: eye(1.5, 0.8, 0, -1) }) },
    'stretch-up': { label: 'Stretch up', pose: createPose({ pitch: 7, roll: -3, squash: -0.14, lift: -12, gazeY: -4, leftEye: eye(1.12, 0.3, 0, -1), rightEye: eye(1.12, 0.3, 0, -1) }) },
    'bouncy-beaming': {
      label: 'Bouncy beaming',
      pose: createPose({ pitch: -4, yaw: -8, roll: 6, squash: 0.04, lift: -4, leftEye: eye(1.3, 1.38, 0, -2, -5), rightEye: eye(1.3, 1.38, 0, -2, 5) }),
      motion: motion('boing'),
    },
    // Hover: eyes swivel inward at the cursor, slightly crossed, with a
    // faint wobble to sell the effort of focusing on something that close.
    'cross-eyed': {
      label: 'Cross-eyed',
      pose: createPose({ pitch: -3, roll: 2, squash: 0.02, gazeY: -1, leftEye: eye(0.92, 0.96, 8, 0, 8), rightEye: eye(0.92, 0.96, -8, 0, -8) }),
      motion: motion('none', 'micro-saccades'),
    },
    // Thinking: eyes dart (micro-saccades) while he snaps between looking up,
    // sideways and down, with an "aha" pop thrown in.
    'think-up': {
      label: 'Think (up)',
      pose: createPose({ pitch: 6, yaw: 14, roll: -8, gazeX: 4, gazeY: -9, leftEye: eye(1.0, 0.92), rightEye: eye(1.0, 0.92) }),
      motion: motion('slow-drift', 'micro-saccades'),
    },
    'think-side': {
      label: 'Think (side)',
      pose: createPose({ pitch: -3, yaw: -17, roll: 6, squash: 0.03, gazeX: -6, leftEye: eye(1.06, 0.62, 0, -1, -6), rightEye: eye(0.96, 1.0, 0, 1, 4) }),
      motion: motion('none', 'micro-saccades'),
    },
    'think-down': {
      label: 'Think (down)',
      pose: createPose({ pitch: -11, yaw: 5, roll: -3, gazeY: 6, leftEye: eye(1.0, 0.86), rightEye: eye(1.0, 0.86) }),
      motion: motion('none', 'micro-saccades'),
    },
    'think-pop': { label: 'Think (pop)', pose: createPose({ pitch: 2, squash: -0.06, lift: -7, gazeY: -3, leftEye: eye(1.15, 1.15), rightEye: eye(1.15, 1.15) }) },
    perky: { label: 'Perky', pose: createPose({ pitch: 3, squash: -0.04, lift: -3, gazeY: -2, leftEye: eye(1, 1.1), rightEye: eye(1, 1.1) }) },

    // --- fidget poses
    'glance-left': { label: 'Glance left', pose: createPose({ pitch: -2, yaw: -20, roll: -3, gazeX: -7, leftEye: eye(0.96, 1.02), rightEye: eye(1, 0.98) }) },
    'glance-right': { label: 'Glance right', pose: createPose({ pitch: -2, yaw: 20, roll: 3, gazeX: 7, leftEye: eye(1, 0.98), rightEye: eye(0.96, 1.02) }) },
    'tilt-left': { label: 'Tilt left', pose: createPose({ pitch: -4, yaw: -4, roll: -17, gazeX: -2, squash: 0.02, leftEye: eye(1, 1.06, 0, 1), rightEye: eye(1, 0.94, 0, -1) }) },
    'tilt-right': { label: 'Tilt right', pose: createPose({ pitch: -4, yaw: 4, roll: 17, gazeX: 2, squash: 0.02, leftEye: eye(1, 0.94, 0, -1), rightEye: eye(1, 1.06, 0, 1) }) },
    'peek-down': { label: 'Peek down', pose: createPose({ pitch: -17, yaw: 3, roll: 2, lift: 6, gazeY: 9, leftEye: eye(1.05, 0.9), rightEye: eye(1.05, 0.9) }) },
    'wiggle-left': { label: 'Wiggle left', pose: createPose({ yaw: -9, roll: -11, squash: 0.05, lift: 3, leftEye: eye(1.04, 0.96), rightEye: eye(1.04, 0.96) }) },
    'wiggle-right': { label: 'Wiggle right', pose: createPose({ yaw: 9, roll: 11, squash: 0.05, lift: 3, leftEye: eye(1.04, 0.96), rightEye: eye(1.04, 0.96) }) },
    yawning: { label: 'Yawning', pose: createPose({ pitch: 9, roll: 2, squash: -0.07, lift: -5, gazeY: -2, leftEye: eye(1.2, 0.16), rightEye: eye(1.2, 0.16) }) },
    'yawn-peak': { label: 'Yawn peak', pose: createPose({ pitch: 12, roll: 3, squash: -0.1, lift: -8, gazeY: -3, leftEye: eye(1.25, 0.08), rightEye: eye(1.25, 0.08) }) },

    // --- sleep cycle
    drowsy: {
      label: 'Drowsy',
      pose: createPose({ pitch: -6, roll: 4, squash: 0.03, lift: 2, gazeY: 4, leftEye: eye(1.2, 0.42), rightEye: eye(1.2, 0.42) }),
      motion: motion('slow-drift'),
    },
    nodding: { label: 'Nodding', pose: createPose({ pitch: -24, roll: 3, squash: 0.1, lift: 12, gazeY: 6, leftEye: eye(1.22, 0.14), rightEye: eye(1.22, 0.14) }) },
    // Asleep he deflates: squashed low and wide, sagging on the ground, with
    // a shallow breath (exhale = asleep, inhale = asleep-inhale).
    asleep: { label: 'Asleep', pose: createPose({ pitch: -12, roll: 7, squash: 0.19, lift: 20, gazeY: 4, leftEye: eye(1.32, 0.08, 0, 1), rightEye: eye(1.32, 0.08, 0, 1) }) },
    'asleep-inhale': { label: 'Asleep (inhale)', pose: createPose({ pitch: -10, roll: 6, squash: 0.14, lift: 15, gazeY: 4, leftEye: eye(1.32, 0.08, 0, 1), rightEye: eye(1.32, 0.08, 0, 1) }) },
    'asleep-shift': { label: 'Asleep (shift)', pose: createPose({ pitch: -12, yaw: 8, roll: -6, squash: 0.19, lift: 20, gazeY: 4, leftEye: eye(1.32, 0.08, 0, 1), rightEye: eye(1.32, 0.08, 0, 1) }) },
  }
  for (const name of Object.keys(expressions)) {
    if (def.expressions[name]) continue
    const expression = expressions[name]
    expression.motion = Object.assign(motion(), expression.motion)
    def.expressions[name] = expression
  }

  const step = (expression, holdMs, transitionMs, easing = 'gentle') => ({ expression, holdMs, transitionMs, easing })
  const once = (label, steps, extra) => Object.assign({ label, playback: 'once', ambient: 0.3, blink: 'normal', steps }, extra)
  const loop = (label, steps, extra) => Object.assign({ label, playback: 'loop', ambient: 0.4, blink: 'normal', steps }, extra)

  const animations = {
    // Replacements for stock faces (bouncier, more varied).
    idle: loop('Idle', [
      step('neutral', 3800, 700),
      step('curious', 2600, 760),
      step('neutral', 3200, 720),
      step('soft-gaze', 2400, 800),
      step('glance-right', 1900, 680),
      step('neutral', 4200, 720),
      step('perky', 1700, 620, 'spring'),
    ], { ambient: 0.46 }),
    happy: loop('Happy', [
      step('soft-gaze', 1200, 520, 'spring'),
      step('bouncy-beaming', 2400, 620, 'spring'),
      step('cheeky', 1600, 570),
    ], { ambient: 0.48, blink: 'bright' }),
    thinking: loop('Thinking', [
      step('think-up', 700, 320, 'quick'),
      step('think-side', 600, 300, 'quick'),
      step('think-down', 500, 280, 'quick'),
      step('think-up', 800, 340, 'quick'),
      step('think-pop', 240, 260, 'spring'),
      step('think-side', 700, 300, 'quick'),
      step('skyward', 600, 360, 'quick'),
    ], { ambient: 0.55, blink: 'bright' }),
    surprised: once('Surprised', [
      step('neutral', 60, 110, 'quick'),
      step('squished', 90, 150, 'quick'),
      step('startled', 1150, 380, 'spring'),
      step('curious', 800, 760),
    ], { ambient: 0.22, blink: 'bright' }),
    'victory-bounce': once('Victory bounce', [
      step('shy', 180, 160, 'quick'),
      step('squished', 90, 150, 'quick'),
      step('stretched', 220, 200, 'quick'),
      step('landing', 90, 190, 'quick'),
      step('bouncy-beaming', 1200, 400, 'spring'),
      step('cheeky', 850, 420, 'spring'),
      step('confident', 1400, 760),
    ], { ambient: 0.54, blink: 'bright' }),
    sleeping: loop('Sleeping', [
      step('asleep', 1900, 2100),
      step('asleep-inhale', 800, 2300),
      step('asleep', 2100, 2100),
      step('asleep-inhale', 800, 2300),
      step('asleep-shift', 2600, 2400),
      step('asleep-inhale', 700, 2300),
    ], { ambient: 0.1, blink: 'none' }),

    // Idle variants (Widget.qml rotates between these while idling).
    'idle-perky': loop('Idle (perky)', [
      step('perky', 2400, 600, 'spring'),
      step('curious', 2200, 700),
      step('neutral', 2800, 700),
      step('glance-left', 1600, 640),
      step('skyward', 1800, 760),
    ], { ambient: 0.52, blink: 'bright' }),
    'idle-drowsy': loop('Idle (drowsy)', [
      step('drowsy', 3800, 1200),
      step('soft-gaze', 2400, 1100),
      step('sleepy', 3200, 1300),
      step('drowsy', 3000, 1200),
    ], { ambient: 0.24, blink: 'sleepy' }),
    excited: loop('Excited', [
      step('bouncy-beaming', 2200, 500, 'spring'),
      step('perky', 700, 380, 'spring'),
      step('bouncy-beaming', 1800, 520, 'spring'),
      step('cheeky', 900, 480, 'spring'),
    ], { ambient: 0.5, blink: 'bright' }),

    // Fidget one-shots.
    hop: once('Hop', [
      step('neutral', 60, 140, 'quick'),
      step('squished', 100, 150, 'quick'),
      step('stretched', 140, 220),
      step('landing', 90, 300, 'spring'),
      step('neutral', 300, 0),
    ]),
    bounce: once('Bounce', [
      step('neutral', 60, 140, 'quick'),
      step('squished', 100, 150, 'quick'),
      step('stretched', 130, 210),
      step('landing', 80, 170, 'quick'),
      step('hop-mini', 110, 190),
      step('landing', 70, 300, 'spring'),
      step('neutral', 300, 0),
    ], { ambient: 0.4, blink: 'bright' }),
    glance: once('Glance', [
      step('neutral', 80, 420),
      step('glance-left', 900, 520),
      step('glance-right', 1100, 560),
      step('neutral', 300, 0),
    ]),
    tilt: once('Tilt', [
      step('neutral', 80, 520, 'spring'),
      step('tilt-left', 1500, 620),
      step('neutral', 300, 0),
    ]),
    'tilt-right': once('Tilt right', [
      step('neutral', 80, 520, 'spring'),
      step('tilt-right', 1500, 620),
      step('neutral', 300, 0),
    ]),
    peek: once('Peek', [
      step('neutral', 80, 600),
      step('peek-down', 1800, 700),
      step('curious', 600, 600),
      step('neutral', 300, 0),
    ]),
    wiggle: once('Wiggle', [
      step('neutral', 40, 200, 'quick'),
      step('wiggle-left', 60, 190, 'quick'),
      step('wiggle-right', 60, 190, 'quick'),
      step('wiggle-left', 60, 190, 'quick'),
      step('wiggle-right', 60, 320, 'spring'),
      step('neutral', 300, 0),
    ], { ambient: 0.3, blink: 'bright' }),
    stretch: once('Stretch', [
      step('neutral', 80, 600),
      step('stretch-up', 1300, 500),
      step('landing', 120, 420, 'spring'),
      step('neutral', 300, 0),
    ]),
    'look-around': once('Look around', [
      step('neutral', 80, 460),
      step('glance-left', 800, 560),
      step('skyward', 900, 600),
      step('glance-right', 800, 560),
      step('neutral', 300, 0),
    ]),
    yawn: once('Yawn', [
      step('neutral', 100, 700),
      step('yawning', 500, 600),
      step('yawn-peak', 900, 900),
      step('drowsy', 700, 800),
      step('neutral', 200, 0),
    ], { ambient: 0.24, blink: 'sleepy', mouth: 'o', mouthScale: 1.25 }),

    // Sleep transitions: dozing → sleeping (loop) → waking.
    dozing: once('Dozing off', [
      step('neutral', 100, 1400),
      step('drowsy', 2200, 1500),
      step('nodding', 500, 1400),
      step('drowsy', 1600, 1300),
      step('nodding', 600, 1600),
      step('asleep', 600, 0),
    ], { ambient: 0.18, blink: 'sleepy' }),
    waking: once('Waking', [
      step('asleep', 80, 480, 'quick'),
      step('surprised', 420, 420, 'spring'),
      step('stretch-up', 1100, 600),
      step('landing', 110, 360, 'spring'),
      step('neutral', 400, 0),
    ], { ambient: 0.3, blink: 'bright' }),
  }
  const replaced = ['idle', 'thinking', 'happy', 'surprised', 'victory-bounce', 'sleeping']
  for (const name of Object.keys(animations)) {
    if (def.animations[name] && replaced.indexOf(name) === -1) continue
    const usable = animations[name].steps.every(s => def.expressions[s.expression])
    if (usable) def.animations[name] = animations[name]
  }
}

// Animations whose `mouth` flag makes the controller draw a mouth (see
// mouth.mjs) — a flapping "o" while speaking, and static curved smile/frown
// bands.
export function addMouthAnimations(def) {
  const extras = {
    speaking: {
      label: 'Speaking', playback: 'loop', ambient: 0.4, blink: 'normal', mouth: 'flap', mouthRequired: true,
      steps: [
        { expression: 'focused', holdMs: 2100, transitionMs: 600, easing: 'gentle' },
        { expression: 'confident', holdMs: 1500, transitionMs: 640, easing: 'gentle' },
        { expression: 'soft-gaze', holdMs: 1300, transitionMs: 580, easing: 'gentle' },
        { expression: 'focused', holdMs: 1800, transitionMs: 620, easing: 'gentle' },
      ],
    },
    smiling: {
      label: 'Smiling', playback: 'loop', ambient: 0.42, blink: 'bright', mouth: 'smile', mouthRequired: true,
      steps: [
        { expression: 'beaming', holdMs: 2000, transitionMs: 620, easing: 'spring' },
        { expression: 'cheeky', holdMs: 1600, transitionMs: 580, easing: 'gentle' },
        { expression: 'beaming', holdMs: 1800, transitionMs: 600, easing: 'gentle' },
        { expression: 'soft-gaze', holdMs: 1400, transitionMs: 640, easing: 'gentle' },
      ],
    },
    frowning: {
      label: 'Frowning', playback: 'loop', ambient: 0.2, blink: 'sleepy', mouth: 'frown', mouthRequired: true,
      steps: [
        { expression: 'sad', holdMs: 2600, transitionMs: 800, easing: 'gentle' },
        { expression: 'uneasy', holdMs: 2000, transitionMs: 700, easing: 'gentle' },
        { expression: 'sad', holdMs: 2400, transitionMs: 760, easing: 'gentle' },
      ],
    },
  }
  for (const name of Object.keys(extras)) {
    if (def.animations[name]) continue
    const usable = extras[name].steps.every(step => def.expressions[step.expression])
    if (usable) def.animations[name] = extras[name]
  }

  // Give every stock face a fitting mouth. These only render while the mouth
  // toggle is on, and never overwrite a mouth the definition already carries.
  const animationMouths = {
    idle: ['line', 0.8], listening: ['line', 0.7], thinking: ['line', 0.75],
    happy: ['smile', 1], curious: ['o', 0.5], surprised: ['o', 1],
    shy: ['line', 0.55], sad: ['frown', 0.9], 'stand-tall': ['smile', 0.85],
    'victory-bounce': ['smile', 1.1], sleeping: ['line', 0.5],
    'idle-perky': ['smile', 0.7], 'idle-drowsy': ['line', 0.6], excited: ['smile', 1.1],
    hop: ['smile', 0.9], bounce: ['smile', 1], glance: ['line', 0.75], tilt: ['line', 0.75],
    'tilt-right': ['line', 0.75], peek: ['o', 0.5], wiggle: ['line', 0.7], stretch: ['line', 0.6],
    'look-around': ['line', 0.75], dozing: ['line', 0.6], waking: ['o', 0.8],
  }
  const expressionMouths = {
    neutral: ['line', 0.8], focused: ['line', 0.7], curious: ['o', 0.5],
    skyward: ['line', 0.7], 'soft-gaze': ['line', 0.75], 'side-eye': ['line', 0.6],
    beaming: ['smile', 1], cheeky: ['smile', 0.85], surprised: ['o', 1],
    shy: ['line', 0.55], sad: ['frown', 0.9], sleepy: ['line', 0.6],
    confident: ['smile', 0.8], angry: ['frown', 1], uneasy: ['frown', 0.7],
    squished: ['line', 0.9], landing: ['line', 0.85], stretched: ['o', 0.6], startled: ['o', 1.1],
    'bouncy-beaming': ['smile', 1], perky: ['smile', 0.7], drowsy: ['line', 0.6], 'cross-eyed': ['o', 0.45],
    'think-up': ['line', 0.7], 'think-side': ['line', 0.6], 'think-down': ['line', 0.7], 'think-pop': ['o', 0.7],
    nodding: ['line', 0.5], asleep: ['line', 0.5], yawning: ['o', 1.2], 'yawn-peak': ['o', 1.35],
  }
  for (const name of Object.keys(animationMouths)) {
    const target = def.animations[name]
    if (target && !target.mouth) {
      target.mouth = animationMouths[name][0]
      target.mouthScale = animationMouths[name][1]
    }
  }
  for (const name of Object.keys(expressionMouths)) {
    const target = def.expressions[name]
    if (target && !target.mouth) {
      target.mouth = expressionMouths[name][0]
      target.mouthScale = expressionMouths[name][1]
    }
  }
}
