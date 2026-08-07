/**
 * AudioPlayTracker Hook
 * 
 * Tracks when an audio file starts playing and notifies the server.
 * Only tracks the first play per page load to avoid counting seeks as plays.
 */
export const AudioPlayTracker = {
    mounted() {
        this.hasTracked = false;
        this.logId = this.el.dataset.logId;

        this.el.addEventListener('play', () => {
            if (!this.hasTracked && this.logId) {
                this.hasTracked = true;
                this.pushEvent('track_play', { id: this.logId });
                console.log('[AudioPlayTracker] Tracked play for log:', this.logId);
            }
        });
    }
};
