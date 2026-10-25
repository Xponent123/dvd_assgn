# 4-bit array multiplier: RTL to GDSII

| Team member | Roll number |
|---|---|
| Jal Parikh | 2023102066 |
| Garima Mittal | 2023102069 |


## Individual contributions

Both members contributed equally to this assignment. Jal Parikh (2023102066) wrote the RTL (`full_adder.v`, `mult_array.v`), the STA script with the T_min/F_max analysis, and the LibreLane configuration and timing-closure runs. Garima Mittal (2023102069) wrote the exhaustive self-checking testbench and the fault-injection test, the synthesis script with gate-level simulation, and the physical-design analysis (metrics, DRC/LVS checks and layout views). We debugged the design, answered the report questions and reviewed the README and report together.

For ECE463 Digital VLSI, we implemented a 4-bit unsigned array multiplier and took
it through simulation, synthesis, static timing analysis and physical design on
SKY130. Our RTL has 16 partial-product AND operations, 12 explicit full adders and
16 register bits. All registers use an asynchronous active-low reset. We used
Jal's roll number for the worked example: A = 6 + 5 = 11, B = 7, so P = 77.
The calculations, screenshots, required tables and six answers are in
[report.pdf](report.pdf).

## Results

| Measurement | Our result |
|---|---|
| RTL and mapped simulation at 10 ns | 256 vectors checked, 0 errors in each |
| Deliberate full-adder sum fault | 256 vectors checked, 95 errors |
| Part B cells / cell area | 63 / 740.7104 µm² |
| Flip-flops / flip-flop area | 16 / 400.384 µm² (54.05%) |
| Part C slack at 10 / 2.60 / 2.61 ns | +7.396 / −0.004 / +0.006 ns |
| Part C estimated minimum period / Fmax | 2.604 ns / 384.025 MHz |
| Part D CLOCK_PERIOD / clock rate | 6.5 ns / 153.846 MHz |
| Part D calculated throughput / guide latency (2T) | 153.846 million results/s / 13 ns |
| Part D post-route Fmax estimate from worst-corner slack | 155.891 MHz |
| Part D post-route Fmax, nominal typical corner: 1000/(6.5 − 3.292673) | 311.786 MHz |
| Part D final setup / hold slack | +0.085280 / +0.124205 ns |
| Part D physical instances / core area / routed wirelength | 1901 / 17759.5 µm² / 2405 µm |
| Part D Magic DRC / KLayout DRC / LVS / slew violations | 0 / 0 / 0 / 0 |

Latency is 2 clock cycles (inputs are captured at edge 1, the product at edge 2);
following the assignment, latency in ns = 2 × T. We use this **2T latency
convention** in the results tables and show both edges in the waveform. The
pipeline accepts one input pair per clock, without a multicycle constraint.

## Repository

```text
<repository>/
  README.md
  rtl/full_adder.v
  rtl/mult_array.v
  tb/tb_mult.v
  synth/synth.tcl
  synth/mult_array_netlist.v
  synth/mult_array_stat.rpt
  sta/sta.tcl
  sta/mult_array_timing.rpt
  pnr/config.json
  pnr/metrics.json
  pnr/mult_array.gds
  report/report.pdf
```

Run the following steps from the repository root. The simulation outputs
(`sim`, `gls`, `mult.vcd`) and the LibreLane `pnr/runs/` directory are build
products and are not committed.

## 1. Environment

We used `hpretl/iic-osic-tools:2026.09`, pinned to the image digest below.
On a Linux host with Docker, open a shell from the repository root:

```bash
docker run --rm -it --user "$(id -u):$(id -g)" --cpus 4 --memory 8g \
  --shm-size 256m -e PDK=sky130A \
  -v "$PWD:/foss/designs/team:rw" -w /foss/designs/team \
  hpretl/iic-osic-tools@sha256:b87b3f1af9ba72d9486466ea777cf4248e96e20d9dba76d67259bc185db3859c \
  -s /bin/bash -l
```

In that container, use the same shell session for the remaining commands:

```bash
set -euo pipefail
project_root="$PWD"
build_root="$(mktemp -d /tmp/mult4-XXXXXX)"
cell_dir="$PDK_ROOT/sky130A/libs.ref/sky130_fd_sc_hd/verilog"
mkdir -p "$build_root/rtl" "$build_root/fault" "$build_root/gls" "$build_root/logs"
printf 'Build evidence: %s\n' "$build_root"
iverilog -V
yosys -V
sta -version
librelane --version
klayout -v
```

Our recorded versions are Icarus 14.0 devel (`s20260301-477-gd1982fc7-dirty`),
Yosys 0.69 (`9f75ca1f9`), OpenSTA 3.1.0 (`f89887b596`), LibreLane 3.1.0.dev3,
OpenROAD `26Q3-2443-g50432012f`, KLayout 0.30.12, Magic 8.3.684 and
Netgen 1.5.323. The PDK revision is `1689ac3f2dc763876eaf967227c7dfe831b031ae`;
`PDK_ROOT=/foss/pdks`, `PDK=sky130A` and the library is `sky130_fd_sc_hd`.
Our standalone synthesis and STA scripts use the typical-corner file
`sky130_fd_sc_hd__tt_025C_1v80.lib`.


## 2. Part A: RTL simulation and error test

```bash
iverilog -g2012 -o sim tb/tb_mult.v rtl/full_adder.v rtl/mult_array.v
vvp sim
gtkwave mult.vcd
```

Expected output:

```text
PASS: 256 vectors checked, 0 errors
```

For the required error test, we temporarily change the sum assignment in
`rtl/full_adder.v` from `assign sum  = a ^ b ^ cin;` to `assign sum  = a ^ b;`, and re-run the same
`iverilog` and `vvp` commands. The testbench then prints
`FAIL: 256 vectors checked, 95 errors`. We then undo the change and re-run both commands to get
`PASS: 256 vectors checked, 0 errors` again. The submitted RTL contains no
multiplication operator; the basic testbench uses multiplication for its
expected result.

We release reset at 20 ns, after two full clock periods. Our testbench counts
actual comparisons, rejects unknown values with `!==`, and fails if it has not
checked all 256 pairs. Its waveform file is `mult.vcd`.

In GTKWave we display clk, rst_n, a, b and p with decimal bus values. Our 11 × 7
example is applied at 3690 ns, captured into the input registers at 3695 ns and
captured into p as 77 at 3705 ns.

#### Optional: automated version of the fault test (isolated copy)

```bash
iverilog -g2012 -o "$build_root/rtl/sim" tb/tb_mult.v rtl/full_adder.v rtl/mult_array.v
(cd "$build_root/rtl"; vvp ./sim) > "$build_root/logs/rtl.log" 2>&1
cat "$build_root/logs/rtl.log"
python3 - "$project_root" "$build_root" <<'PY'
from pathlib import Path
import sys
project, build = map(Path, sys.argv[1:])
source = (project / 'rtl/full_adder.v').read_text()
assert source.count('a ^ b ^ cin') == 1
(build / 'fault/full_adder.v').write_text(source.replace('a ^ b ^ cin', 'a ^ b'))
PY
iverilog -g2012 -o "$build_root/fault/sim" tb/tb_mult.v \
  "$build_root/fault/full_adder.v" rtl/mult_array.v
if (cd "$build_root/fault"; vvp ./sim) > "$build_root/logs/fault.log" 2>&1; then
  echo 'ERROR: the deliberate sum fault was not detected'
  exit 1
fi
grep 'FAIL: 256 vectors checked, 95 errors' "$build_root/logs/fault.log"
(cd "$build_root/rtl"; vvp ./sim) > "$build_root/logs/restored.log" 2>&1
cat "$build_root/logs/restored.log"
```

In this version the waveform file is `$build_root/rtl/mult.vcd`.

## 3. Part B: synthesis and gate-level simulation

```bash
yosys -c synth/synth.tcl
CELLS=$PDK_ROOT/sky130A/libs.ref/sky130_fd_sc_hd/verilog
iverilog -g2012 -DFUNCTIONAL -DUNIT_DELAY=#1 -o gls tb/tb_mult.v $CELLS/primitives.v $CELLS/sky130_fd_sc_hd.v synth/mult_array_netlist.v
vvp gls
```

Expected output of the gate-level simulation:

```text
PASS: 256 vectors checked, 0 errors
```

Equivalent variant that writes its build products and logs to `$build_root`:

```bash
yosys -c synth/synth.tcl > "$build_root/logs/synthesis.log" 2>&1
iverilog -g2012 -DFUNCTIONAL '-DUNIT_DELAY=#1' -o "$build_root/gls/sim" \
  tb/tb_mult.v "$cell_dir/primitives.v" "$cell_dir/sky130_fd_sc_hd.v" \
  synth/mult_array_netlist.v
(cd "$build_root/gls"; vvp ./sim) > "$build_root/logs/gls.log" 2>&1
cat "$build_root/logs/gls.log"
```

Our script follows the seven synthesis operations specified in the assignment.
The result has 16 `dfrtp_1` flip-flops and 47 combinational cells. The three
most-used types are `dfrtp_1` ×16, `nand2_1` ×8 and `a21oi_1` ×6. Our mapped
simulation also prints `PASS: 256 vectors checked, 0 errors`.

The mapped netlist includes two `lpflow_isobufsrc_1` cells whose function is
`A & ~SLEEP`; they are used as ordinary combinational logic here. LibreLane
excludes `lpflow_*` cells in its own synthesis run, which produces 68 cells.
We therefore distinguish our 63-cell Part B result from the physical flow's
separate synthesis result.

## 4. Part C: static timing analysis

```bash
sta -exit sta/sta.tcl > "$build_root/logs/sta_10ns.log" 2>&1
cp sta/mult_array_timing.rpt "$build_root/logs/timing_10ns.rpt"
STA_PERIOD=2.60 sta -exit sta/sta.tcl > "$build_root/logs/sta_2p60ns.log" 2>&1
cp sta/mult_array_timing.rpt "$build_root/logs/timing_2p60ns.rpt"
STA_PERIOD=2.61 sta -exit sta/sta.tcl > "$build_root/logs/sta_2p61ns.log" 2>&1
cp sta/mult_array_timing.rpt "$build_root/logs/timing_2p61ns.rpt"
cp "$build_root/logs/timing_2p60ns.rpt" sta/mult_array_timing.rpt
grep 'worst slack' "$build_root/logs/sta_10ns.log" "$build_root/logs/sta_2p60ns.log" "$build_root/logs/sta_2p61ns.log"
```

`sta/sta.tcl` uses T = 10 ns unless the environment variable `STA_PERIOD` is set,
and each run overwrites `sta/mult_array_timing.rpt`. The commands above run T = 10 ns
first (WNS +7.396 ns), then T = 2.60 ns, then T = 2.61 ns, and the last `cp`
restores the 2.60 ns report. The committed `sta/mult_array_timing.rpt` is the
T = 2.60 ns run (Tmin 2.604 rounded to 0.01 ns), with slack −0.004 ns; OpenSTA labels it
"VIOLATED" only because of this rounding. T = 2.61 ns gives +0.006 ns.

We obtained Tmin = 10 − 7.396 = **2.604 ns** and Fmax = 1000 / 2.604 =
**384.025 MHz** from the printed slack. At the required rounded period of
2.60 ns, slack is −0.004 ns; at 2.61 ns, it is +0.006 ns. We submit the 2.60 ns
timing report. Following the guide, latency at Tmin is 5.208 ns and throughput
is 384.025 million results/s. These values are calculated timing estimates.

Our critical setup path is:

```text
a_reg[1] _095_/Q
  -> _039_/Y clkinv_1    : ~a_reg[1]
  -> _047_/Y o311ai_0    : factored partial-product / row-1 term
  -> _050_/Y a21oi_1     : c2[1]
  -> _063_/X maj3_1      : c2[2]
  -> _064_/Y xnor2_1     : ~s2[2]
  -> _066_/X maj3_1      : ~c3[2]
  -> _075_/X maj3_1      : ~c3[3]
  -> _079_/X xnor3_1     : s3[3] = product_comb[6]
  -> p[6] _092_/D
```

We count eight combinational cells, or ten cells if we include the launch and
capture flip-flops. Six cells directly match full-adder output functions, one
combines a partial-product/row-1 term, and one inverts an operand bit. We cannot
assign that factored term exclusively to an intact full adder. Our RTL also has
an eight-adder structural route, consistent with the guide's approximate 2N
estimate, but technology mapping does not preserve eight separate adder blocks.

The report's first path is a noncritical reset-recovery path; the setup path
above is in clock group clk. We use OpenSTA's reported slack because the other
printed timing fields are rounded separately.

## 5. Part D: physical design

Our initial period was 0.5 × ceil(1.2 × 2.604 / 0.5) = **3.5 ns**. We increased
it in 0.5 ns steps until setup timing passed. We then enabled post-global-route
repair and increased its slew margin to clear the remaining reset-network slew
violations. Our final `pnr/config.json` contains the settings in the last row.

| Attempt / run tag | Period (ns) | Post-GRT repair | Slew margin (%) | Setup slack (ns) | Slew violations | Magic DRC | KLayout DRC | LVS | Result |
|---|---:|---|---:|---:|---:|---:|---:|---:|---|
| attempt_01_3p5ns | 3.5 | false | 10 | −2.129189 | 0 | 0 | 0 | 0 | FAIL (setup) |
| attempt_02_4p0ns | 4.0 | false | 10 | −1.629189 | 0 | 0 | 0 | 0 | FAIL (setup) |
| attempt_03_4p5ns | 4.5 | false | 10 | −1.139431 | 0 | 0 | 0 | 0 | FAIL (setup) |
| attempt_04_5p0ns | 5.0 | false | 10 | −0.641733 | 0 | 0 | 0 | 0 | FAIL (setup) |
| attempt_05_5p5ns | 5.5 | false | 10 | −0.141733 | 0 | 0 | 0 | 0 | FAIL (setup) |
| attempt_06_6p0ns | 6.0 | false | 10 | −0.064138 | 11 | 0 | 0 | 0 | FAIL (setup, slew) |
| attempt_07_6p5ns | 6.5 | false | 10 | +0.085280 | 11 | 0 | 0 | 0 | FAIL (slew) |
| attempt_08_6p5ns_repair | 6.5 | true | 10 | +0.085280 | 11 | 0 | 0 | 0 | FAIL (slew) |
| attempt_09_6p5ns_repair | 6.5 | true | 20 | +0.085280 | 0 | 0 | 0 | 0 | PASS |

The repair margin controls how aggressively the flow repairs slew; our signoff
transition limit remains 0.750 ns. We did not disable signoff checks.

We added `RUN_POST_GRT_DESIGN_REPAIR` and `GRT_DESIGN_REPAIR_MAX_SLEW_PCT` = 20
(neither is required by the assignment) because runs 6–8 left 11 reset-net slew
violations; with the 20 % margin, run 9 has 0.

### Reproduce the final run

From the repository root, we run LibreLane in `pnr/` and copy the metrics and GDS
from the same run:

```bash
cd pnr
librelane --manual-pdk --pdk-root /foss/pdks --pdk sky130A --scl sky130_fd_sc_hd --run-tag attempt_09_6p5ns_repair config.json
cp runs/attempt_09_6p5ns_repair/final/metrics.json metrics.json
cp runs/attempt_09_6p5ns_repair/final/gds/mult_array.gds mult_array.gds
cd ..
klayout pnr/mult_array.gds
```

`pnr/runs/` is not committed (the assignment says not to commit runs/).

We retain the run's netlists, SDC, SPEF, logs and reports locally. The committed pnr/config.json is the attempt 9 configuration (CLOCK_PERIOD 6.5 ns, RUN_POST_GRT_DESIGN_REPAIR true, GRT_DESIGN_REPAIR_MAX_SLEW_PCT 20). pnr/metrics.json and pnr/mult_array.gds were copied from run attempt_09_6p5ns_repair. The table records the archived runs; we have
not repeated all nine physical runs for this documentation revision.

```bash
sha256sum pnr/mult_array.gds pnr/metrics.json
05b512ab995d81d6ea0dcfce9f6392aa85c789697f64fbed7ec1492e7da7763f  pnr/mult_array.gds
a8a93aabb3ffeb669cf32eeecd9e277e823be3bb8c31bd62a1c028b69c4747e1  pnr/metrics.json
```

To view the layout with the SKY130 layer properties:

```bash
klayout -l "$PDK_ROOT/sky130A/libs.tech/klayout/tech/sky130A.lyp" pnr/mult_array.gds
```

In KLayout, our screenshots show the whole
150 × 150 µm die and a close-up at x = 40–95 µm, y = 42.8125–77.1875 µm,
with the hierarchy expanded to show cell rows and metal routing.

### Cell counts and timing after routing

| Count | What we counted |
|---:|---|
| 63 | Part B mapped cells |
| 68 | LibreLane synthesis cells |
| 17 | Port buffers: 9 input and 8 output |
| 2 | Reset fanout buffers: one `buf_2`, one `clkdlybuf4s50_1` |
| 3 | Clock buffers |
| 90 | Functional cells and signal/clock buffers |
| 245 | Tap cells |
| 335 | Standard-cell metric, excluding the fill class |
| 269 + 1297 | Filler and decap instances |
| 1901 | All final physical instances |

We checked the insertion and repair logs: both reset fanout buffers started as
delay cells, and post-global-route repair changed `fanout18` to `buf_2`.
Fillers and decaps occupy about 93.0% of the core. The standard-cell utilization
is about 6.96%; the 68 functional logic/register cells alone occupy about 4.25%.

Our final worst-corner setup path runs from `a_reg[0]` (`_104_`) to `p[6]`
(`_102_`). Its constraints include 0.25 ns clock uncertainty, 1.3 ns I/O delays,
propagated clocks and 0.95/1.05 early/late derates. We do not add I/O delays to
this register-to-register path. Our worst setup corner is `max_ss_100C_1v60`;
the nominal-RC, typical `nom_tt_025C_1v80` result gives a separate 311.786 MHz estimate.
Different mappings, corners, extracted RC and clock timing all affect the
Part C/Part D comparison, so we cannot isolate their costs from the two Fmax
values alone.

We use final metric keys `timing__setup__ws`, `timing__hold__ws`,
`route__wirelength`, `design__core__area`, `design__instance__count`,
`magic__drc_error__count`, `klayout__drc_error__count` and
`design__lvs_error__count`. Our archived logs include intermediate routing DRC
counts of 9, 3, 4 and then 0, and early VGND/VPWR floating-net warnings. The
final supply connectivity and LVS checks pass.

## Assumptions and limits

- We calculate Fmax from static slack using `1000 / (period − setup slack)`.
  This assumes the same implemented circuit, constraints and corner when we
  adjust the clock period. It is an estimate, not a measured silicon frequency;
  our delivered layout was closed at 6.5 ns.
- Latency is 2 clock cycles (inputs are captured at edge 1, the product at edge 2); following the assignment, latency in ns = 2 × T.
  The waveform shows both capture edges.
  Our throughput calculations assume continuous inputs after pipeline fill,
  with reset inactive.
- Our mapped simulations use the library's artificial `UNIT_DELAY=#1`
  functional model. The required test runs at 10 ns; we use 20 ns for the
  extended mapped test. These simulations verify function, not extracted timing.
- Our optional formal proof uses zero initialization and the `async2sync`
  abstraction. We check off-edge asynchronous-reset behavior separately in
  simulation.
- The report's 8-bit delay estimate assumes comparable delay per adder stage.
  We have not synthesized or routed an 8-bit version.
- Our physical claims use the archived final reports and metrics. This revision
  updates the documentation; it does not claim a new place-and-route run.


## References

- Assignment: `RTL_to_GDS.pdf`, especially Sections 2 and 5–11.
- [Yosys command reference](https://yosyshq.readthedocs.io/projects/yosys/en/stable/cmd-cmd.html): synthesis and optional proof commands.
- [OpenSTA command reference](https://opensta.readthedocs.io/en/latest/Commands/): clock, delay and timing-report commands. We use installed-command help for version-specific details.
- [LibreLane step configuration](https://librelane.readthedocs.io/en/latest/reference/step_config_vars.html): mapping, repair and signoff settings.
- [OpenROAD Gate Resizer](https://openroad.readthedocs.io/en/latest/main/src/rsz/README.html): port buffering, design repair and timing repair.
- [SKY130 high-density library](https://skywater-pdk.readthedocs.io/en/main/contents/libraries/sky130_fd_sc_hd/README.html): cell library; we used the installed Liberty and Verilog files for exact areas and functions.

## 6. Extra checks (not required by the assignment)

The required commands above use no plusargs.

### Temporary-directory replay of the final run

This runs our submitted configuration in a temporary copy and collects the GDS
and metrics from the same run:

```bash
mkdir -p "$build_root/physical"
cp -r rtl pnr "$build_root/physical/"
(
  cd "$build_root/physical/pnr"
  librelane --manual-pdk --pdk-root /foss/pdks --pdk sky130A \
    --scl sky130_fd_sc_hd --jobs 4 --run-tag reproduce_final \
    --hide-progress-bar config.json
) > "$build_root/logs/physical.log" 2>&1
final_run="$build_root/physical/pnr/runs/reproduce_final/final"
python3 - "$final_run/metrics.json" <<'PY'
from pathlib import Path
import json, sys
m = json.loads(Path(sys.argv[1]).read_text())
for key in ['magic__drc_error__count', 'klayout__drc_error__count',
            'design__lvs_error__count', 'design__max_slew_violation__count']:
    assert m[key] == 0, (key, m[key])
assert m['timing__setup__ws'] >= 0
assert m['timing__hold__ws'] >= 0
print('Physical signoff metrics pass')
PY
mkdir -p "$build_root/collected"
cp "$final_run/metrics.json" "$build_root/collected/metrics.json"
cp "$final_run/gds/mult_array.gds" "$build_root/collected/mult_array.gds"
```

### Replay the nine recorded configurations

The following creates a separate copy for every attempt and runs the same
LibreLane command with that attempt's three settings. Failed timing/transition
checks are expected in attempts 1–8, so we retain the return code and continue
when final metrics are available. This is an optional full replay; it is not
needed after a successful final-only run.

```bash
python3 - "$project_root" "$build_root" <<'PY'
from pathlib import Path
import json, shutil, subprocess, sys
project, build = map(Path, sys.argv[1:])
base = json.loads((project / 'pnr/config.json').read_text())
attempts = [
    ('attempt_01_3p5ns', 3.5, False, 10),
    ('attempt_02_4p0ns', 4.0, False, 10),
    ('attempt_03_4p5ns', 4.5, False, 10),
    ('attempt_04_5p0ns', 5.0, False, 10),
    ('attempt_05_5p5ns', 5.5, False, 10),
    ('attempt_06_6p0ns', 6.0, False, 10),
    ('attempt_07_6p5ns', 6.5, False, 10),
    ('attempt_08_6p5ns_repair', 6.5, True, 10),
    ('attempt_09_6p5ns_repair', 6.5, True, 20),
]
for tag, period, repair, margin in attempts:
    trial = build / 'replay' / tag
    shutil.copytree(project / 'rtl', trial / 'rtl')
    (trial / 'pnr').mkdir()
    config = dict(base, CLOCK_PERIOD=period,
                  RUN_POST_GRT_DESIGN_REPAIR=repair,
                  GRT_DESIGN_REPAIR_MAX_SLEW_PCT=margin)
    (trial / 'pnr/config.json').write_text(json.dumps(config, indent=2) + '\n')
    command = ['librelane', '--manual-pdk', '--pdk-root', '/foss/pdks',
               '--pdk', 'sky130A', '--scl', 'sky130_fd_sc_hd', '--jobs', '4',
               '--run-tag', tag, '--hide-progress-bar', 'config.json']
    with (build / 'logs' / f'{tag}.log').open('w') as log:
        result = subprocess.run(command, cwd=trial / 'pnr', stdout=log,
                                stderr=subprocess.STDOUT)
    metrics_file = trial / 'pnr/runs' / tag / 'final/metrics.json'
    if not metrics_file.is_file():
        raise RuntimeError(f'{tag}: no final metrics; inspect its log')
    m = json.loads(metrics_file.read_text())
    print(tag, 'exit=', result.returncode, 'setup=', m['timing__setup__ws'],
          'slew=', m['design__max_slew_violation__count'])
PY
```

### Extended testbench mode, mutation tests and formal proof

We also added streaming and reset checks using the same submitted testbench:

```bash
(cd "$build_root/rtl"; vvp ./sim +EXTENDED) > "$build_root/logs/rtl_extended.log" 2>&1
(cd "$build_root/gls"; vvp ./sim +EXTENDED +HALF_PERIOD=10) > "$build_root/logs/gls_extended.log" 2>&1
cat "$build_root/logs/rtl_extended.log"
cat "$build_root/logs/gls_extended.log"
```

Our extended test uses shifted addition as a second reference. It applies 256
unique input pairs on consecutive cycles, checks the preceding transaction's
product, and checks pipeline drain/restart. Three off-edge resets use products
225, 182 and 77. Across those tests, every register bit is first exercised high
and then checked clear before the next rising edge. We get `EXTENDED PASS` on
both RTL and our named-register Part B netlist.

We tested the assertions against two deliberately broken variants:

```bash
python3 - "$project_root" "$build_root" <<'PY'
from pathlib import Path
import sys
project, build = map(Path, sys.argv[1:])
rtl = (project / 'rtl/mult_array.v').read_text()
(build / 'sync_reset.v').write_text(rtl.replace('posedge clk or negedge rst_n', 'posedge clk'))
(build / 'bypass_input_regs.v').write_text(rtl.replace('= a_reg & {4{b_reg[', '= a & {4{b['))
PY
for variant in sync_reset bypass_input_regs; do
  iverilog -g2012 -o "$build_root/$variant" tb/tb_mult.v rtl/full_adder.v "$build_root/$variant.v"
  if (cd "$build_root"; vvp "./$variant" +EXTENDED) > "$build_root/logs/$variant.log" 2>&1; then
    echo "ERROR: $variant escaped detection"
    exit 1
  fi
  grep 'FATAL:' "$build_root/logs/$variant.log"
done
```

We get `ASYNC RESET` for the synchronous-reset variant and `PIPELINE` for the
input-register bypass. These variants passed the basic exhaustive procedure,
which is why we kept the additional checks.

Our optional formal cross-check uses the following complete reference and proof:

```bash
cat > "$build_root/formal_reference.v" <<'VERILOG'
module formal_reference(input clk, rst_n, input [3:0] a,b, output ok);
    wire [7:0] actual;
    reg [3:0] ref_a, ref_b;
    reg [7:0] ref_p;
    mult_array dut(.clk(clk),.rst_n(rst_n),.a(a),.b(b),.p(actual));
    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin ref_a<=0; ref_b<=0; ref_p<=0; end
        else begin ref_a<=a; ref_b<=b; ref_p<=ref_a * ref_b; end
    assign ok = actual == ref_p;
endmodule
VERILOG
yosys -p "read_verilog -formal rtl/full_adder.v rtl/mult_array.v $build_root/formal_reference.v; prep -top formal_reference -flatten; async2sync; opt; sat -seq 4 -set-init-zero -set-def-inputs -prove ok 1 -tempinduct -maxsteps 8 -verify" > "$build_root/logs/formal.log" 2>&1
grep 'SUCCESS' "$build_root/logs/formal.log"
```

### Re-running the default RTL test for the waveform

If an extended run has overwritten the waveform, rerun the default RTL test:

```bash
(cd "$build_root/rtl"; vvp ./sim) > "$build_root/logs/rtl_waveform.log" 2>&1
```

```bash
gtkwave "$build_root/rtl/mult.vcd"
```
