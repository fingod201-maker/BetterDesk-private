"use client";

import { useRouter } from "next/navigation";
import { Camera, CameraOff, Mic, MicOff } from "lucide-react";
import { useEffect, useRef, useState, type FormEvent, type KeyboardEvent } from "react";

export default function JoinMeetingForm({ meetingId, initialStream }: { meetingId: string; initialStream: MediaStream | null }) {
  const router = useRouter();
  const [name, setName] = useState("");
  const [rememberName, setRememberName] = useState(false);
  const [joining, setJoining] = useState(false);
  const [mediaStream, setMediaStream] = useState<MediaStream | null>(initialStream);
  const [videoEnabled, setVideoEnabled] = useState(true);
  const [audioEnabled, setAudioEnabled] = useState(true);
  const videoRef = useRef<HTMLVideoElement>(null);
  const streamRef = useRef<MediaStream | null>(null);

  useEffect(() => {
    const savedName = window.localStorage.getItem("zoom-meeting-name");
    if (savedName) {
      queueMicrotask(() => {
        setName(savedName);
        setRememberName(true);
      });
    }

    return () => {
      streamRef.current?.getTracks().forEach((track) => track.stop());
      streamRef.current = null;
    };
  }, []);

  useEffect(() => {
    if (initialStream) {
      streamRef.current = initialStream;
      queueMicrotask(() => setMediaStream(initialStream));
    }
  }, [initialStream]);

  useEffect(() => {
    if (videoRef.current && mediaStream) videoRef.current.srcObject = mediaStream;
  }, [mediaStream]);

  function toggleVideo() {
    const enabled = !videoEnabled;
    mediaStream?.getVideoTracks().forEach((track) => { track.enabled = enabled; });
    setVideoEnabled(enabled);
  }

  function toggleAudio() {
    const enabled = !audioEnabled;
    mediaStream?.getAudioTracks().forEach((track) => { track.enabled = enabled; });
    setAudioEnabled(enabled);
  }

  function toggleRememberName() {
    setRememberName((remembered) => !remembered);
  }

  function handleRememberKeyDown(event: KeyboardEvent<HTMLDivElement>) {
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      toggleRememberName();
    }
  }

  function backToLaunch() {
    const passcode = new URLSearchParams(window.location.search).get("pwd");
    const query = passcode ? `?pwd=${encodeURIComponent(passcode)}#success` : "#success";
    router.push(`/j/${meetingId}${query}`);
  }

  function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!name.trim()) return;

    if (rememberName) window.localStorage.setItem("zoom-meeting-name", name.trim());
    else window.localStorage.removeItem("zoom-meeting-name");

    setJoining(true);
  }

  const hasName = Boolean(name.trim());

  return (
    <div className="prejoin-screen">
      <button className="btn-back-pwa" type="button" onClick={backToLaunch}>
        <svg xmlns="http://www.w3.org/2000/svg" width="1em" height="1em" fill="none" viewBox="0 0 16 16" className="btn-back-pwa-icon" aria-hidden="true">
          <path fill="currentColor" fillRule="evenodd" d="m5.635 8.339.037.037 3.978 3.978a.5.5 0 1 0 .706-.708L6.715 8.004l3.639-3.65a.5.5 0 0 0 0-.708.5.5 0 0 0-.707 0L5.731 7.575a.502.502 0 0 0-.096.764" clipRule="evenodd" />
        </svg>
        Back
      </button>

      <section className="prejoin-layout" aria-label="Join meeting">
        <div className="camera-preview" aria-label="Camera preview">
          {mediaStream && videoEnabled ? (
            <video ref={videoRef} autoPlay muted playsInline />
          ) : (
            <div className="preview-video__default-avatar" style={{ zIndex: 1 }}>
              <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" fill="none" viewBox="0 0 16 16" className="SvgPreviewDefaultAvatar" aria-hidden="true">
                <mask id="___SVG_ID__1__0___" width="14" height="12" x="1" y="2" maskUnits="userSpaceOnUse" style={{ maskType: "alpha" }}>
                  <path fill="#000001" fillRule="evenodd" d="M1.218 3.092C1 3.52 1 4.08 1 5.2v5.6c0 1.12 0 1.68.218 2.108a2 2 0 0 0 .874.874C2.52 14 3.08 14 4.2 14h7.6c1.12 0 1.68 0 2.108-.218a2 2 0 0 0 .874-.874C15 12.48 15 11.92 15 10.8V5.2c0-1.12 0-1.68-.218-2.108a2 2 0 0 0-.874-.874C13.48 2 12.92 2 11.8 2H4.2c-1.12 0-1.68 0-2.108.218a2 2 0 0 0-.874.874M8 8.933a2.133 2.133 0 1 0 0-4.266 2.133 2.133 0 0 0 0 4.266M8 10c-2.4 0-4 1.075-4 2.4 0 .212.041.415.116.6h7.768c.075-.185.116-.388.116-.6 0-.509-.236-.98-.662-1.37C10.653 10.409 9.478 10 8 10" clipRule="evenodd" />
                </mask>
                <g mask="url(#___SVG_ID__1__0___)"><rect width="16" height="16" fill="currentColor" /></g>
              </svg>
            </div>
          )}

          <div className="preview-controls">
            <button type="button" onClick={toggleAudio} disabled={!mediaStream} aria-label={audioEnabled ? "Mute" : "Unmute"}>
              {audioEnabled ? <Mic size={18} /> : <MicOff size={18} />}
              <span>{audioEnabled ? "Mute" : "Unmute"}</span>
            </button>
            <button type="button" onClick={toggleVideo} disabled={!mediaStream} aria-label={videoEnabled ? "Stop Video" : "Start Video"}>
              {videoEnabled ? <Camera size={18} /> : <CameraOff size={18} />}
              <span>{videoEnabled ? "Stop Video" : "Start Video"}</span>
            </button>
          </div>
        </div>

        <form className="preview-meeting-info" onSubmit={submit}>
          <div className="preview-meeting-info__title">Enter Meeting Info</div>
          <div className="preview-meeting-info__field">
            <label className="preview-meeting-info__field-title" htmlFor="input-for-name">Your Name</label>
            <div className="preview-meeting-info__field-input">
              <input
                id="input-for-name"
                name="inputname"
                type="text"
                autoComplete="off"
                required
                aria-invalid="false"
                aria-describedby="error-for-name"
                maxLength={128}
                value={name}
                onChange={(event) => setName(event.target.value)}
              />
              <span id="error-for-name" className="sr-only">Enter your name to join the meeting.</span>
            </div>
          </div>
          <div className="captcha-placeholder" aria-hidden="true" />
          <div
            className="zm-checkbox preview-remember-name"
            role="checkbox"
            tabIndex={0}
            aria-checked={rememberName}
            onClick={toggleRememberName}
            onKeyDown={handleRememberKeyDown}
          >
            <span className="zm-checkbox-box" aria-hidden="true">{rememberName ? "✓" : ""}</span>
            <span className="zm-checkbox-message">Remember my name for future meetings</span>
          </div>
          <button
            type="submit"
            className={`zm-btn preview-join-button${hasName && !joining ? "" : " disabled zm-btn__outline--blue zm-btn--disabled"}`}
            tabIndex={hasName && !joining ? 0 : -1}
            disabled={!hasName || joining}
          >
            Join<span className="loading" style={{ display: joining ? "inline-block" : "none" }} />
          </button>
          <div className="preview-agreement">
            By clicking &quot;Join&quot;, you agree to our <a href="https://app.zoom.us/terms" target="_blank" rel="noopener noreferrer" aria-label="Terms of Service">Terms of Service</a> and <a href="https://app.zoom.us/privacy" target="_blank" rel="noopener noreferrer" aria-label="Privacy Statement">Privacy Statement</a>.
          </div>
          <div className="recaptcha_tos">
            Zoom is protected by reCAPTCHA and their&nbsp;<a href="https://policies.google.com/privacy" target="_blank" rel="noreferrer noopener">Privacy Policy</a>&nbsp;and&nbsp;<a href="https://policies.google.com/terms" target="_blank" rel="noreferrer noopener">Terms of Service</a>&nbsp;apply.
          </div>
        </form>
      </section>
    </div>
  );
}
