// squigglebot extension: the stock mascot definition, in one place.
//
// Builds an open-mascot definition from squigglebot's options (shape, colors,
// eye geometry) and dresses it with the mouth set — the dedicated speaking/
// smiling/frowning loops plus a fitting default mouth for every stock face.
//
// shell.qml currently carries its own copy of this wiring in
// buildDefinition()/addMouthAnimations(); it should migrate to this module so
// the desktop mascot and the bar widget (Widget.qml) stay one definition.

import { createDefinition } from './definition.mjs'
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
  addMouthAnimations(def)
  return def
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
    'victory-bounce': ['smile', 1.1], sleeping: ['line', 0.6],
  }
  const expressionMouths = {
    neutral: ['line', 0.8], focused: ['line', 0.7], curious: ['o', 0.5],
    skyward: ['line', 0.7], 'soft-gaze': ['line', 0.75], 'side-eye': ['line', 0.6],
    beaming: ['smile', 1], cheeky: ['smile', 0.85], surprised: ['o', 1],
    shy: ['line', 0.55], sad: ['frown', 0.9], sleepy: ['line', 0.6],
    confident: ['smile', 0.8], angry: ['frown', 1], uneasy: ['frown', 0.7],
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
