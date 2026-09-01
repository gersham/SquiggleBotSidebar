// squigglebot extension (not part of upstream open-mascot): a small round
// mouth, surface-mapped onto the blob with the same projection the eyes use,
// that flaps open and closed while a speaking animation plays.
import { _internals } from './scene.mjs'

const clamp = (value, lo, hi) => Math.min(hi, Math.max(lo, value))

// Rhythmic, syllable-ish open amount: a fast flap modulated by a slower
// cadence so it reads as speech rather than a metronome.
export const flapOpenAt = elapsedMs => {
  const t = Math.max(0, elapsedMs) / 1000
  const syllables = Math.abs(Math.sin(t * 6.8))
  const cadence = 0.55 + 0.45 * Math.sin(t * 1.9 + 1)
  return clamp(0.1 + syllables * cadence, 0.08, 1)
}

// Oval outline used by the flapping mouth and the static "o".
const ovalOutline = (width, height) => {
  const samples = 40
  const points = []
  for (let index = 0; index < samples; index += 1) {
    const angle = (index / samples) * Math.PI * 2
    points.push([(width / 2) * Math.cos(angle), (height / 2) * Math.sin(angle)])
  }
  return points
}

const flapOutline = (face, open) => ovalOutline(
  (face.mouthWidth ?? 17) * (0.82 + 0.3 * open),
  Math.max(3, (face.mouthHeight ?? 19) * (0.16 + 0.84 * open)),
)

// Static open "o": scale 1 is a big surprised mouth, ~0.5 a small "oh?".
const oOutline = (face, scale) => ovalOutline(
  (face.mouthWidth ?? 17) * (0.7 + 0.5 * scale),
  (face.mouthHeight ?? 19) * (0.35 + 0.75 * scale),
)

// Curved band for smiles (+1), frowns (-1), and flat lines (0): a parabola
// with a thickness that tapers toward the corners so the ends read rounded.
const curveOutline = (face, direction, scale) => {
  const width = (face.mouthCurveWidth ?? 34) * (direction === 0 ? 0.62 : 1) * scale
  const depth = (face.mouthCurveDepth ?? 9) * direction * scale
  const thickness = (face.mouthThickness ?? 6) * (0.8 + 0.2 * scale)
  const samples = 22
  const top = []
  const bottom = []
  for (let index = 0; index <= samples; index += 1) {
    const t = index / samples
    const x = (t - 0.5) * width
    const y = depth * (1 - 4 * (t - 0.5) ** 2)
    const half = (thickness * (0.55 + 0.45 * Math.sin(Math.PI * t))) / 2
    top.push([x, y - half])
    bottom.push([x, y + half])
  }
  bottom.reverse()
  return top.concat(bottom)
}

export const MOUTH_MODES = ['flap', 'smile', 'frown', 'line', 'o']

// grow (0..1) squashes the mouth toward a closed sliver so shape changes can
// shrink out and grow back in instead of popping between outlines.
export const buildMouth = (definition, pose, elapsedMs, mode = 'flap', scale = 1, grow = 1) => {
  const { blob, face } = definition
  const open = mode === 'flap' ? flapOpenAt(elapsedMs) : 0
  let outline = mode === 'smile' ? curveOutline(face, 1, scale)
    : mode === 'frown' ? curveOutline(face, -1, scale)
    : mode === 'line' ? curveOutline(face, 0, scale)
    : mode === 'o' ? oOutline(face, scale)
    : flapOutline(face, open)
  if (grow < 1) {
    const g = clamp(grow, 0, 1)
    outline = outline.map(([x, y]) => [x * (0.7 + 0.3 * g), y * g])
  }
  // The mouth follows the head more than the gaze, so damp the gaze offset.
  const centerX = pose.gaze.x * 0.5
  const centerY = (face.mouthY ?? 46) + pose.gaze.y * 0.4
  const bodyDepth = Math.min(blob.width, blob.height) * (150 / 220)
  const points = outline.map(([x, y]) => {
    const surfaceX = centerX + x
    const surfaceY = centerY + y
    return _internals.projectPoint([
      surfaceX,
      surfaceY,
      _internals.bodySurfaceDepth(surfaceX, surfaceY, blob.width, blob.height, bodyDepth) + 1.4,
    ], pose.blob)
  })
  return {
    path: _internals.smoothClosedPath(points),
    fill: face.mouthColor ?? face.eyeColor,
    open,
    mode,
  }
}
