/**
 * AudioRecorder Hook for Phoenix LiveView
 * 
 * A robust audio recording hook with clear state management.
 * 
 * Workflow:
 *   1. IDLE: User clicks Record -> starts recording
 *   2. RECORDING: User clicks Stop -> stops recording, enters PREVIEW
 *   3. PREVIEW: User can Play preview, then Save Draft / Publish / Discard
 *   4. On save: Audio data is sent to server via pushEvent
 *   5. On discard: Returns to IDLE
 */
export const AudioRecorder = {
    mounted() {
        console.log('[AudioRecorder] Mounting hook...');

        this.state = 'idle'; // idle, recording, preview
        this.stream = null;
        this.mediaRecorder = null;
        this.chunks = [];
        this.audioBlob = null;
        this.audioUrl = null;
        this.audioCtx = null;
        this.analyser = null;
        this.animationId = null;

        // Get UI elements
        this.recordBtn = document.getElementById('record-btn');
        this.statusEl = document.getElementById('recording-status');
        this.canvas = document.getElementById('visualizer');
        this.placeholder = document.getElementById('visualizer-placeholder');
        this.previewSection = document.getElementById('preview-section');
        this.previewAudio = document.getElementById('preview-audio');
        this.actionsSection = document.getElementById('action-buttons');

        // Debug: log what elements we found
        console.log('[AudioRecorder] Elements found:', {
            recordBtn: !!this.recordBtn,
            statusEl: !!this.statusEl,
            canvas: !!this.canvas,
            previewSection: !!this.previewSection,
            previewAudio: !!this.previewAudio,
            actionsSection: !!this.actionsSection
        });

        // Bind record button
        if (this.recordBtn) {
            this.recordBtn.onclick = (e) => {
                e.preventDefault();
                this.handleRecordClick();
            };
            console.log('[AudioRecorder] Record button bound');
        } else {
            console.error('[AudioRecorder] Record button not found!');
        }

        // Bind action buttons
        const btnDraft = document.getElementById('btn-save-draft');
        const btnPublish = document.getElementById('btn-publish');
        const btnDiscard = document.getElementById('btn-discard');

        if (btnDraft) {
            btnDraft.onclick = (e) => {
                e.preventDefault();
                this.saveRecording('draft');
            };
        }
        if (btnPublish) {
            btnPublish.onclick = (e) => {
                e.preventDefault();
                this.saveRecording('publish');
            };
        }
        if (btnDiscard) {
            btnDiscard.onclick = (e) => {
                e.preventDefault();
                this.discardRecording();
            };
        }

        // Listen for server events
        this.handleEvent('reset_recorder', () => {
            console.log('[AudioRecorder] Received reset_recorder event');
            this.resetToIdle();
        });

        this.handleEvent('save_complete', (payload) => {
            console.log('[AudioRecorder] Save complete:', payload);
            this.resetToIdle();
        });

        console.log('[AudioRecorder] Hook mounted successfully');
    },

    handleRecordClick() {
        console.log('[AudioRecorder] Record button clicked, state:', this.state);

        if (this.state === 'idle') {
            this.startRecording();
        } else if (this.state === 'recording') {
            this.stopRecording();
        }
    },

    async startRecording() {
        try {
            console.log('[AudioRecorder] Requesting microphone access...');

            this.stream = await navigator.mediaDevices.getUserMedia({ audio: true });
            console.log('[AudioRecorder] Microphone access granted');

            // Determine best mime type
            let mimeType = 'audio/webm';
            if (MediaRecorder.isTypeSupported('audio/webm;codecs=opus')) {
                mimeType = 'audio/webm;codecs=opus';
            } else if (MediaRecorder.isTypeSupported('audio/webm')) {
                mimeType = 'audio/webm';
            } else if (MediaRecorder.isTypeSupported('audio/ogg;codecs=opus')) {
                mimeType = 'audio/ogg;codecs=opus';
            }
            console.log('[AudioRecorder] Using mime type:', mimeType);

            this.mediaRecorder = new MediaRecorder(this.stream, { mimeType });
            this.chunks = [];

            this.mediaRecorder.ondataavailable = (e) => {
                if (e.data.size > 0) {
                    this.chunks.push(e.data);
                }
            };

            this.mediaRecorder.onstop = () => {
                console.log('[AudioRecorder] MediaRecorder stopped, chunks:', this.chunks.length);
                this.audioBlob = new Blob(this.chunks, { type: mimeType });
                this.audioUrl = URL.createObjectURL(this.audioBlob);
                console.log('[AudioRecorder] Blob created, size:', this.audioBlob.size);
                this.enterPreviewState();
            };

            this.mediaRecorder.start(100);
            this.state = 'recording';
            this.updateUI();
            this.startVisualization();

            console.log('[AudioRecorder] Recording started');

        } catch (err) {
            console.error('[AudioRecorder] Error starting recording:', err);
            if (this.statusEl) {
                this.statusEl.textContent = 'Error: ' + err.message;
                this.statusEl.style.color = '#ef4444';
            }
        }
    },

    stopRecording() {
        console.log('[AudioRecorder] Stopping recording...');

        if (this.mediaRecorder && this.mediaRecorder.state === 'recording') {
            this.mediaRecorder.stop();
        }

        this.stopVisualization();

        if (this.stream) {
            this.stream.getTracks().forEach(track => track.stop());
        }
    },

    enterPreviewState() {
        this.state = 'preview';

        if (this.previewAudio && this.audioUrl) {
            this.previewAudio.src = this.audioUrl;
        }

        this.updateUI();
        console.log('[AudioRecorder] Entered preview state');
    },

    saveRecording(action) {
        if (!this.audioBlob) {
            console.error('[AudioRecorder] No audio blob to save');
            return;
        }

        console.log('[AudioRecorder] Saving recording, action:', action, 'size:', this.audioBlob.size);

        // Update UI to show saving
        if (this.statusEl) {
            this.statusEl.textContent = 'Saving...';
            this.statusEl.style.color = '#fbbf24';
        }

        // Disable buttons while saving
        const btnDraft = document.getElementById('btn-save-draft');
        const btnPublish = document.getElementById('btn-publish');
        const btnDiscard = document.getElementById('btn-discard');
        if (btnDraft) btnDraft.disabled = true;
        if (btnPublish) btnPublish.disabled = true;
        if (btnDiscard) btnDiscard.disabled = true;

        // Convert blob to base64 and send to server
        const reader = new FileReader();
        reader.onloadend = () => {
            const base64data = reader.result;
            console.log('[AudioRecorder] Sending to server, base64 length:', base64data.length);

            // Push to LiveView
            this.pushEvent('save_audio_recording', {
                audio_data: base64data,
                action: action,
                filename: `captains_log_${Date.now()}.webm`,
                mime_type: this.audioBlob.type
            });
        };
        reader.onerror = (err) => {
            console.error('[AudioRecorder] Error reading blob:', err);
            if (this.statusEl) {
                this.statusEl.textContent = 'Error saving';
                this.statusEl.style.color = '#ef4444';
            }
        };
        reader.readAsDataURL(this.audioBlob);
    },

    discardRecording() {
        console.log('[AudioRecorder] Discarding recording');
        this.resetToIdle();
    },

    resetToIdle() {
        this.state = 'idle';
        this.chunks = [];

        if (this.audioUrl) {
            URL.revokeObjectURL(this.audioUrl);
            this.audioUrl = null;
        }
        this.audioBlob = null;

        if (this.previewAudio) {
            this.previewAudio.pause();
            this.previewAudio.src = '';
        }

        // Re-enable buttons
        const btnDraft = document.getElementById('btn-save-draft');
        const btnPublish = document.getElementById('btn-publish');
        const btnDiscard = document.getElementById('btn-discard');
        if (btnDraft) btnDraft.disabled = false;
        if (btnPublish) btnPublish.disabled = false;
        if (btnDiscard) btnDiscard.disabled = false;

        this.stopVisualization();
        this.updateUI();

        console.log('[AudioRecorder] Reset to idle');
    },

    updateUI() {
        // Record button
        if (this.recordBtn) {
            if (this.state === 'idle') {
                this.recordBtn.innerHTML = '<i class="fas fa-microphone"></i>';
                this.recordBtn.style.background = '#ef4444';
                this.recordBtn.style.boxShadow = '0 0 30px rgba(239, 68, 68, 0.4), inset 0 -3px 10px rgba(0,0,0,0.3)';
                this.recordBtn.style.borderColor = 'rgba(239, 68, 68, 0.3)';
                this.recordBtn.disabled = false;
            } else if (this.state === 'recording') {
                this.recordBtn.innerHTML = '<i class="fas fa-stop"></i>';
                this.recordBtn.style.background = '#1f2937';
                this.recordBtn.style.boxShadow = '0 0 40px rgba(239, 68, 68, 0.6)';
                this.recordBtn.style.borderColor = '#ef4444';
                this.recordBtn.disabled = false;
            } else if (this.state === 'preview') {
                this.recordBtn.innerHTML = '<i class="fas fa-microphone"></i>';
                this.recordBtn.style.background = '#374151';
                this.recordBtn.style.boxShadow = 'none';
                this.recordBtn.style.borderColor = '#555';
                this.recordBtn.disabled = true;
            }
        }

        // Status text
        if (this.statusEl) {
            if (this.state === 'idle') {
                this.statusEl.textContent = 'Ready to Record';
                this.statusEl.style.color = '#888';
            } else if (this.state === 'recording') {
                this.statusEl.textContent = '● RECORDING';
                this.statusEl.style.color = '#ef4444';
            } else if (this.state === 'preview') {
                this.statusEl.textContent = 'Recording Complete';
                this.statusEl.style.color = '#4ade80';
            }
        }

        // Canvas/placeholder
        if (this.canvas && this.placeholder) {
            if (this.state === 'recording') {
                this.canvas.style.display = 'block';
                this.placeholder.style.display = 'none';
            } else {
                this.canvas.style.display = 'none';
                this.placeholder.style.display = 'block';
            }
        }

        // Preview section
        if (this.previewSection) {
            this.previewSection.style.display = this.state === 'preview' ? 'block' : 'none';
        }

        // Action buttons
        if (this.actionsSection) {
            this.actionsSection.style.display = this.state === 'preview' ? 'flex' : 'none';
        }
    },

    startVisualization() {
        if (!this.canvas || !this.stream) return;

        const ctx = this.canvas.getContext('2d');

        try {
            this.audioCtx = new (window.AudioContext || window.webkitAudioContext)();
            const source = this.audioCtx.createMediaStreamSource(this.stream);
            this.analyser = this.audioCtx.createAnalyser();
            this.analyser.fftSize = 256;
            source.connect(this.analyser);

            const bufferLength = this.analyser.frequencyBinCount;
            const dataArray = new Uint8Array(bufferLength);

            const draw = () => {
                if (this.state !== 'recording') return;

                this.animationId = requestAnimationFrame(draw);
                this.analyser.getByteFrequencyData(dataArray);

                ctx.fillStyle = '#000';
                ctx.fillRect(0, 0, this.canvas.width, this.canvas.height);

                const barWidth = (this.canvas.width / bufferLength) * 2.5;
                let x = 0;

                for (let i = 0; i < bufferLength; i++) {
                    const barHeight = (dataArray[i] / 255) * this.canvas.height;
                    const hue = 30 - (dataArray[i] / 255) * 20;
                    ctx.fillStyle = `hsl(${hue}, 100%, 50%)`;
                    ctx.fillRect(x, this.canvas.height - barHeight, barWidth, barHeight);
                    x += barWidth + 1;
                }
            };

            draw();
        } catch (err) {
            console.error('[AudioRecorder] Visualization error:', err);
        }
    },

    stopVisualization() {
        if (this.animationId) {
            cancelAnimationFrame(this.animationId);
            this.animationId = null;
        }

        if (this.audioCtx) {
            try {
                this.audioCtx.close();
            } catch (e) { }
            this.audioCtx = null;
        }

        if (this.canvas) {
            const ctx = this.canvas.getContext('2d');
            ctx.fillStyle = '#000';
            ctx.fillRect(0, 0, this.canvas.width, this.canvas.height);
        }
    },

    destroyed() {
        console.log('[AudioRecorder] Destroying hook');
        this.stopVisualization();
        if (this.stream) {
            this.stream.getTracks().forEach(track => track.stop());
        }
        if (this.audioUrl) {
            URL.revokeObjectURL(this.audioUrl);
        }
    }
};
