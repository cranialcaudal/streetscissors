# tools/film/test-model/

A **pretend roll of film whose every number is known**, used to test the colour maths.

## Why it exists

`film-develop` turns a scan of a negative back into a positive picture. To know whether it does
that *correctly*, you would need to know what the scene really looked like, which with a real
photograph you never do. So [`synth.py`](synth.py) runs the process forwards instead:

1. It invents a scene: patches of exactly known colour and brightness.
2. It "exposes" them onto a model of a film whose every property is set in the code: how
   sensitive each colour layer is, how dense the dyes become, the orange tint of colour negative
   film.
3. It "scans" that film with a model of a flatbed scanner, including the scanner's own small
   errors (stray light, noise).
4. It writes the result as a 16-bit TIFF, exactly like a real scan, plus a `truth.json` file
   holding every number it used.

A test then gives that TIFF to the real tools and checks that they recover the original patches,
within the tolerances written in [`docs/colour/contracts.md`](../../../docs/colour/contracts.md).

The file opens with the full model as equations; read that first.

## Using it

```bash
# Write a fake 3-frame roll of colour negative (c41), black-and-white (bw) or slide (e6) film:
python3 tools/film/test-model/synth.py roll /tmp/fake-roll --process c41 --frames 3

# Run the model's own tests (it checks that its exact inverse gets its numbers back;
# if it could not, nothing tested against it could be trusted):
python3 -m pytest tools/film/test-model
```

You need Python 3 with `numpy` and `pytest` (`pip install numpy pytest`, or Fedora
`sudo dnf install python3-numpy python3-pytest`).

## Files

| File | What it is |
|---|---|
| `synth.py` | The model and a small command line. Deterministic: the same `--seed` always writes the same file |
| `test_synth.py` | Tests of the model itself, for each of the three film processes |
