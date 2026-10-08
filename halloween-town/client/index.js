// halloween-town: bats over Halloween Town (hw_town only).
//
// One full-screen pass (api.graphics.registerPass) drawing a few bats
// flapping across the upper part of the screen, each on its own path and
// speed. Kept deliberately light: no mist or vignette, and the lower part
// of the screen is passed straight through. Off on every other map.

const FRAGMENT = `
const int BATS = 7;

float hash(float n) { return fract(sin(n * 127.1) * 43758.5453); }

// Coverage (0..1) of one bat at p (bat space: body at the origin, wings
// reaching to x = +-1). flap -1..1 lifts and lowers the wing tips.
float bat(vec2 p, float flap, float aa) {
	p.x = abs(p.x);
	// body and head
	float body = length((p - vec2(0.0, -0.02)) * vec2(2.6, 1.5)) - 0.2;
	float head = length(p - vec2(0.0, 0.17)) - 0.09;
	// pointed ears
	vec2 e = p - vec2(0.05, 0.25);
	float ears = max(e.y - 0.1 + abs(e.x) * 2.2, -e.y);
	// wing: thick at the shoulder, tapering to a point at the tip; the tip
	// rises and falls with the flap, the trailing edge is scalloped
	float x = clamp(p.x, 0.0, 1.0);
	float centre = (0.12 + flap * 0.38) * x * x + 0.06 * x;
	float thick = 0.24 * pow(1.0 - x, 0.65);
	float scallop = 0.09 * abs(sin(x * 9.42)) * (1.0 - x) * smoothstep(0.1, 0.3, x);
	float wing = max(max(p.y - (centre + thick * 0.45), (centre - thick + scallop) - p.y), p.x - 1.0);
	float d = min(min(body, head), min(ears, wing));
	return 1.0 - smoothstep(-aa, aa, d);
}

void main() {
	vec2 uv = vUv;
	vec3 color = texture(uTexture, uv).rgb;
	// bats only fly in the upper part of the screen: the rest is passed through
	if (uv.y < 0.44) { fragColor = vec4(color, 1.0); return; }
	float aspect = uResolution.x / uResolution.y;
	vec2 sp = vec2(uv.x * aspect, uv.y);
	float cover = 0.0;
	for (int i = 0; i < BATS; i++) {
		float fi = float(i);
		float size = 0.03 + hash(fi + 3.1) * 0.025;
		float phase = hash(fi + 5.9) * 10.0;
		float t = uTime * (0.035 + hash(fi + 1.3) * 0.05) + phase;
		float dir = hash(fi + 7.7) < 0.5 ? -1.0 : 1.0;
		// across the screen and wrapping, high up, bobbing and swooping
		float x = fract(t) * (aspect + 0.4) - 0.2;
		if (dir < 0.0) x = aspect - x;
		float y = 0.6 + hash(fi + 9.2) * 0.33
			+ sin(uTime * (0.6 + hash(fi + 2.2)) + phase) * 0.04
			+ sin(uTime * 0.23 + fi) * 0.05;
		vec2 p = (sp - vec2(x, y)) / size;
		if (abs(p.x) > 1.3 || abs(p.y) > 1.0) continue;
		p.x *= dir;
		float flap = sin(uTime * (11.0 + hash(fi + 4.4) * 6.0) + phase * 3.0);
		cover = max(cover, bat(p, flap, 1.5 / (size * uResolution.y)));
	}
	fragColor = vec4(mix(color, vec3(0.02, 0.0, 0.03), cover * 0.92), 1.0);
}
`;

const isTown = name => String(name || '').toLowerCase().replace(/\.(gat|rsw)$/, '') === 'hw_town';

export default function init(params, api) {
	if (api?.version !== 1) throw new Error('halloween-town needs client API 1');
	if (!api.graphics?.supported()) {
		console.warn('[halloween-town] this client cannot run graphics passes; no bats');
		return;
	}
	let here = isTown(api.snapshot?.().map);
	api.on('map:enter', ({ name }) => { here = isTown(name); });
	api.on('map:leave', () => { here = false; });
	api.graphics.registerPass({
		name: 'Halloween Town bats',
		fragment: FRAGMENT,
		enabled: () => here,
	});
}
