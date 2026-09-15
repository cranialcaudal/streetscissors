export const GymRoutine = {
    mounted() {
        this.initGym();
    },
    updated() {
        this.initGym();
    },
    initGym() {
        const STORAGE_KEY = 'vault_gym_v1';
        const saved = JSON.parse(localStorage.getItem(STORAGE_KEY) || '{}');
        const resetWeekBtn = this.el.querySelector('#reset-week');

        // Ticks are keyed by scope + the checkbox's position within that scope.
        // The scope is the nearest [data-option] if there is one, else the day.
        //
        // This matters: rotating days (Friday, Saturday) now nest their options
        // inside the day, and every option's checkboxes live in the DOM whether
        // its dropdown is open or not. Keying on position within the *day* would
        // renumber every box the moment an option is added or reordered, quietly
        // moving people's ticks onto different exercises.
        const scopes = this.el.querySelectorAll('[data-option], .day-details');

        scopes.forEach((scope) => {
            const scopeId = scope.dataset.option || scope.dataset.day;

            // Only the boxes belonging to this scope: a day must not claim the
            // ones inside its own nested options.
            const checkboxes = Array.from(
                scope.querySelectorAll('input[type="checkbox"]')
            ).filter((cb) => cb.closest('[data-option], .day-details') === scope);

            checkboxes.forEach((cb, index) => {
                const key = `vault_gym_${scopeId}_${index}`;
                if (saved[key]) cb.checked = true;

                cb.onchange = () => {
                    saved[key] = cb.checked;
                    localStorage.setItem(STORAGE_KEY, JSON.stringify(saved));
                };
            });
        });

        // Week reset
        if (resetWeekBtn) {
            resetWeekBtn.onclick = () => {
                if (confirm("Clear all progress for the week?")) {
                    this.el.querySelectorAll('input[type="checkbox"]').forEach(cb => cb.checked = false);
                    localStorage.setItem(STORAGE_KEY, JSON.stringify({}));
                }
            };
        }

        // --- HOVER LOGIC ---
        const popout = document.getElementById('exercise-hover-popout');
        const thumbContainer = document.getElementById('hover-thumbnail-container');
        const titleEl = document.getElementById('hover-title');
        const muscleEl = document.getElementById('hover-muscle');
        const descEl = document.getElementById('hover-desc');

        if (!popout) return;

        this.el.querySelectorAll('.hover-exercise').forEach(link => {
            link.addEventListener('mouseenter', (e) => {
                const rect = link.getBoundingClientRect();
                const thumbUrl = link.dataset.thumb;
                const muscle = link.dataset.muscle;
                const desc = link.dataset.desc;
                const title = link.textContent;

                // Populate content
                titleEl.textContent = title;
                muscleEl.textContent = muscle ? muscle.replace(/-/g, ' ') : '';
                descEl.textContent = desc || '';
                
                if (thumbUrl) {
                    thumbContainer.innerHTML = `<img src="${thumbUrl}" style="width: 100%; height: 100%; object-fit: cover;" />`;
                    thumbContainer.style.display = 'block';
                } else {
                    thumbContainer.innerHTML = '';
                    thumbContainer.style.display = 'none';
                }

                // Position above the link
                popout.style.display = 'block';
                popout.style.opacity = '0';
                
                // Calculate position relative to document
                const scrollY = window.scrollY;
                const scrollX = window.scrollX;
                
                popout.style.left = `${rect.left + scrollX + (rect.width / 2)}px`;
                popout.style.top = `${rect.top + scrollY - popout.offsetHeight - 15}px`;
                
                // Fade in
                setTimeout(() => popout.style.opacity = '1', 10);
            });

            link.addEventListener('mouseleave', () => {
                popout.style.opacity = '0';
                setTimeout(() => {
                    if (popout.style.opacity === '0') popout.style.display = 'none';
                }, 150);
            });
        });
    }
}
