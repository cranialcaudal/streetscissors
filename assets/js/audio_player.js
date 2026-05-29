/* Audio Player Logic */
export function initAudioPlayer() {
    const playBtn = document.getElementById('play-btn');
    if (!playBtn) return; // Only run on audio page

    const record = document.getElementById('record');
    const tonearm = document.getElementById('tonearm');
    const icon = playBtn.querySelector('i');
    let isPlaying = false;

    playBtn.addEventListener('click', () => {
        isPlaying = !isPlaying;
        if (isPlaying) {
            record.classList.add('playing');
            tonearm.classList.add('playing');
            icon.classList.remove('fa-play');
            icon.classList.add('fa-pause');
        } else {
            record.classList.remove('playing');
            tonearm.classList.remove('playing');
            icon.classList.remove('fa-pause');
            icon.classList.add('fa-play');
        }
    });

    // Simple track selection visual logic
    const tracks = document.querySelectorAll('.track-item');
    tracks.forEach(track => {
        track.addEventListener('click', () => {
            tracks.forEach(t => t.classList.remove('active'));
            track.classList.add('active');
            // Auto play logic would go here
            if (!isPlaying) playBtn.click();
        });
    });
}
