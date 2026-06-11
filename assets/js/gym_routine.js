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
        const dayDetails = this.el.querySelectorAll('.day-details');
        
        dayDetails.forEach((details) => {
            const currentDay = details.dataset.day;
            const checkboxes = details.querySelectorAll('input[type="checkbox"]');

            checkboxes.forEach((cb, index) => {
                // Uniquely identify each checkbox by day and its dom index on that day
                const key = `vault_gym_${currentDay}_${index}`;
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
