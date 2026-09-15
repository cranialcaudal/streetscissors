// Emissions chart controls — vanilla JS, no chart library. Mirrors the
// math in lib/web/blog/embeds.ex's emissions_svg/2 so the client-side
// redraw matches the server-rendered initial SVG exactly. The server
// always renders Frame A, food off, California grid; this file is what
// makes the two emissions figures in their post respond to the
// controls panel (`![[figure:emissions-controls]]`).

const BAR = { width: 640, rowHeight: 44, trackX: 150, maxTrack: 380 };

const LINE = {
    // height 375: ten modes wrap to three legend rows below the plot.
    width: 640, height: 375, left: 72, right: 600, top: 46, bottom: 260,
    legendTopOffset: 42, legendRowHeight: 22, legendColWidth: 140, legendPerRow: 4,
};

const MODE_COLOR = {
    walk: 'var(--ink-4)',
    bicycle: 'var(--color-jade)',
    'e-bike': 'var(--color-dodger)',
    train: 'var(--ink-2)',
    bus: 'var(--ink-3)',
    car: 'var(--color-orange)',
    pickup: 'var(--color-red)',
    plane: 'var(--ink)',
    // The grid modes share the electric blue, lightened by draw -- mirrors
    // @mode_color in lib/web/blog/embeds.ex.
    tesla: 'color-mix(in srgb, var(--color-dodger) 62%, var(--paper))',
    rivian: 'color-mix(in srgb, var(--color-dodger) 78%, var(--ink))',
};

const SVG_NS = 'http://www.w3.org/2000/svg';

function modeSlug(name) {
    return name.toLowerCase().replace(/ /g, '-');
}

function modeColor(name) {
    return MODE_COLOR[modeSlug(name)] || 'var(--ink-3)';
}

function gramsPerMile(mode, state, data) {
    // Grid modes carry kWh per mile and get multiplied by the selected grid
    // intensity (g CO2e/kWh), rather than being overwritten by a fixed g/mi.
    // A Model 3 draws ~14x what an e-bike does, so they can't share a number.
    let g = mode.type === 'grid' ? mode.kwh_per_mile * state.grid : mode.base;
    if (state.food && mode.food_key) {
        g += data.kcal[mode.food_key] * data.diets[state.diet];
    }
    return g;
}

// "Nice" round tick values (0, then multiples of 1/2/5 x a power of ten)
// instead of dividing the raw max into equal thirds -- mirrors
// nice_ticks/1 in lib/web/blog/embeds.ex exactly.
function niceTicks(maxValue) {
    if (maxValue <= 0) return [0, 1];
    const rawStep = maxValue / 4;
    const magnitude = 10 ** Math.floor(Math.log10(rawStep));
    const normalized = rawStep / magnitude;
    let nice;
    if (normalized <= 1) nice = 1;
    else if (normalized <= 2) nice = 2;
    else if (normalized <= 5) nice = 5;
    else nice = 10;
    const step = nice * magnitude;
    const count = Math.ceil(maxValue / step);
    return Array.from({ length: count + 1 }, (_, i) => i * step);
}

function formatLb(v) {
    if (v === 0) return '0 lb';
    return `${Math.round(v).toLocaleString('en-US')} lb`;
}

function renderBarChart(svgEl, data, state) {
    const rows = data.modes.map((m) => {
        // Modes with no NHTS-comparable observed distance (currently just
        // Plane -- commercial flights aren't in that survey) fall back to
        // the Frame A figure for Frame B too, mirroring scripts/emissions.R.
        const miles =
            state.frame === 'a' || m.observed == null ? data.frame_a_one_way_mi : m.observed;
        const gpm = gramsPerMile(m, state, data);
        const monthlyLb = ((gpm * miles * 2 * data.work_days.month) / 1000) * data.kg_to_lb;
        return { name: m.name, sub: m.sub, type: m.type, monthlyLb };
    });

    const maxLb = Math.max(...rows.map((r) => r.monthlyLb), 0);
    const height = rows.length * BAR.rowHeight + 16;
    svgEl.setAttribute('viewBox', `0 0 ${BAR.width} ${height}`);

    if (!svgEl._rowEls) {
        svgEl.textContent = '';
        svgEl._rowEls = rows.map((row, i) => {
            const y = i * BAR.rowHeight;

            const g = document.createElementNS(SVG_NS, 'g');
            g.setAttribute('class', 'fig-bar-row');

            const label = document.createElementNS(SVG_NS, 'text');
            label.setAttribute('x', 0);
            label.setAttribute('y', y + 18);
            label.setAttribute('class', 'fig-bar-label');
            label.textContent = row.name;

            const sub = document.createElementNS(SVG_NS, 'text');
            sub.setAttribute('x', 0);
            sub.setAttribute('y', y + 32);
            sub.setAttribute('class', 'fig-bar-sub');
            sub.textContent = row.sub;

            const rect = document.createElementNS(SVG_NS, 'rect');
            rect.setAttribute('x', BAR.trackX);
            rect.setAttribute('y', y + 6);
            rect.setAttribute('height', 20);

            const value = document.createElementNS(SVG_NS, 'text');
            value.setAttribute('y', y + 6 + 15);
            value.setAttribute('class', 'fig-bar-value');

            g.append(label, sub, rect, value);
            svgEl.appendChild(g);

            return { rect, value };
        });
    }

    // Update in place (not recreate) so the .fig-bar CSS `transition:
    // width` actually has a previous value to animate from.
    rows.forEach((row, i) => {
        const els = svgEl._rowEls[i];
        const trackW = maxLb > 0 ? (row.monthlyLb / maxLb) * BAR.maxTrack : 0;
        const barW = Math.max(trackW, 2);

        els.rect.setAttribute('width', barW.toFixed(2));
        els.rect.setAttribute('class', `fig-bar fig-bar-${row.type}`);
        els.value.setAttribute('x', (BAR.trackX + trackW + 8).toFixed(2));
        // Spelled out, not "kg/mo" -- an abbreviated unit here read as unclear.
        els.value.textContent = `${row.monthlyLb.toFixed(1)} lb/month`;
    });
}

function renderLineChart(svgEl, data, state) {
    const years = data.cumulative.years;
    const oneWay = data.frame_a_one_way_mi;
    const n = years.length;

    const series = data.cumulative.series.map((s) => {
        const mode = data.modes.find((m) => m.name === s.name);
        const gpm = gramsPerMile(mode, state, data);
        const dailyG = gpm * oneWay * 2;
        const yearlyLb = ((dailyG * data.work_days.year) / 1000) * data.kg_to_lb;
        const lb = years.map((y) => Math.round(yearlyLb * y * 10) / 10);
        return { name: s.name, lb };
    });

    const maxLb = Math.max(...series.flatMap((s) => s.lb), 0);
    const yTicks = niceTicks(maxLb);
    const axisMax = yTicks[yTicks.length - 1];
    const xs = Array.from(
        { length: n },
        (_, i) => LINE.left + (i / (n - 1)) * (LINE.right - LINE.left)
    );
    const lineY = (v) => {
        const ratio = axisMax > 0 ? v / axisMax : 0;
        return LINE.bottom - ratio * (LINE.bottom - LINE.top);
    };

    svgEl.textContent = '';
    svgEl.setAttribute('viewBox', `0 0 ${LINE.width} ${LINE.height}`);

    // "Higher is worse" spelled out in the title, not left to be inferred.
    const title = document.createElementNS(SVG_NS, 'text');
    title.setAttribute('x', LINE.left);
    title.setAttribute('y', 20);
    title.setAttribute('class', 'fig-line-axis-title');
    title.textContent = 'Cumulative pounds of CO2e (higher is worse)';
    svgEl.appendChild(title);

    yTicks.forEach((v) => {
        const y = lineY(v);

        const gridline = document.createElementNS(SVG_NS, 'line');
        gridline.setAttribute('x1', LINE.left);
        gridline.setAttribute('y1', y.toFixed(2));
        gridline.setAttribute('x2', LINE.right);
        gridline.setAttribute('y2', y.toFixed(2));
        gridline.setAttribute('class', 'fig-line-gridline');
        svgEl.appendChild(gridline);

        const label = document.createElementNS(SVG_NS, 'text');
        label.setAttribute('x', LINE.left - 8);
        label.setAttribute('y', (y + 4).toFixed(2));
        label.setAttribute('class', 'fig-line-ytick');
        label.setAttribute('text-anchor', 'end');
        label.textContent = formatLb(v);
        svgEl.appendChild(label);
    });

    const axis = document.createElementNS(SVG_NS, 'line');
    axis.setAttribute('x1', LINE.left);
    axis.setAttribute('y1', LINE.bottom);
    axis.setAttribute('x2', LINE.right);
    axis.setAttribute('y2', LINE.bottom);
    axis.setAttribute('class', 'fig-line-axis');
    svgEl.appendChild(axis);

    series.forEach((s) => {
        const g = document.createElementNS(SVG_NS, 'g');
        g.setAttribute('class', 'fig-line-series');
        g.style.setProperty('--mode-color', modeColor(s.name));

        const points = xs
            .map((x, i) => `${x.toFixed(2)},${lineY(s.lb[i]).toFixed(2)}`)
            .join(' ');
        const polyline = document.createElementNS(SVG_NS, 'polyline');
        polyline.setAttribute('points', points);
        polyline.setAttribute('class', 'fig-line');
        g.appendChild(polyline);

        xs.forEach((x, i) => {
            const dot = document.createElementNS(SVG_NS, 'circle');
            dot.setAttribute('cx', x.toFixed(2));
            dot.setAttribute('cy', lineY(s.lb[i]).toFixed(2));
            dot.setAttribute('r', 3.5);
            dot.setAttribute('class', 'fig-line-dot');
            g.appendChild(dot);
        });

        svgEl.appendChild(g);
    });

    xs.forEach((x, i) => {
        const yr = years[i];
        const label = yr === 1 ? '1 yr' : `${yr} yrs`;

        const text = document.createElementNS(SVG_NS, 'text');
        text.setAttribute('x', x.toFixed(2));
        text.setAttribute('y', LINE.bottom + 24);
        text.setAttribute('class', 'fig-line-tick');
        text.setAttribute('text-anchor', 'middle');
        text.textContent = label;
        svgEl.appendChild(text);
    });

    series.forEach((s, i) => {
        const col = i % LINE.legendPerRow;
        const row = Math.floor(i / LINE.legendPerRow);
        const x = LINE.left + col * LINE.legendColWidth;
        const y = LINE.bottom + LINE.legendTopOffset + row * LINE.legendRowHeight;

        const g = document.createElementNS(SVG_NS, 'g');
        g.setAttribute('class', 'fig-legend-item');
        g.style.setProperty('--mode-color', modeColor(s.name));

        const swatch = document.createElementNS(SVG_NS, 'rect');
        swatch.setAttribute('x', x.toFixed(2));
        swatch.setAttribute('y', (y - 9).toFixed(2));
        swatch.setAttribute('width', 10);
        swatch.setAttribute('height', 10);
        swatch.setAttribute('class', 'fig-legend-swatch');
        g.appendChild(swatch);

        const label = document.createElementNS(SVG_NS, 'text');
        label.setAttribute('x', (x + 15).toFixed(2));
        label.setAttribute('y', y.toFixed(2));
        label.setAttribute('class', 'fig-legend-label');
        label.textContent = s.name;
        g.appendChild(label);

        svgEl.appendChild(g);
    });
}

export function initEmissionsControls() {
    const dataEl = document.getElementById('emissions-data');
    if (!dataEl || dataEl.dataset.initialized) return;
    dataEl.dataset.initialized = 'true';

    const data = JSON.parse(dataEl.textContent);
    const barSvg = document.querySelector('.fig-emissions-bar');
    const lineSvg = document.querySelector('.fig-emissions-line');
    const frameInputs = document.querySelectorAll('input[name="emissions-frame"]');
    const foodInput = document.getElementById('emissions-food');
    const dietSelect = document.getElementById('emissions-diet');
    const gridSelect = document.getElementById('emissions-grid');

    // Start on whichever grid the server rendered statically, so the first
    // client-side redraw doesn't silently change the numbers on screen.
    const defaultGrid = (data.grids.find((g) => g.default) || data.grids[0]).g_per_kwh;
    const state = { frame: 'a', food: false, diet: 'us_average', grid: defaultGrid };

    function redraw() {
        if (barSvg) renderBarChart(barSvg, data, state);
        if (lineSvg) renderLineChart(lineSvg, data, state);
    }

    frameInputs.forEach((input) => {
        input.addEventListener('change', () => {
            if (!input.checked) return;
            state.frame = input.value;
            redraw();
        });
    });

    if (foodInput) {
        foodInput.addEventListener('change', () => {
            state.food = foodInput.checked;
            if (dietSelect) dietSelect.disabled = !state.food;
            redraw();
        });
    }

    if (dietSelect) {
        dietSelect.addEventListener('change', () => {
            state.diet = dietSelect.value;
            redraw();
        });
    }

    if (gridSelect) {
        gridSelect.addEventListener('change', () => {
            state.grid = Number(gridSelect.value);
            redraw();
        });
    }

    redraw();
}
