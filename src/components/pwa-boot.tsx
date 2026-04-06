"use client";

import { useEffect, useState } from "react";

type BeforeInstallPromptEvent = Event & {
  prompt: () => Promise<void>;
  userChoice: Promise<{ outcome: "accepted" | "dismissed" }>;
};

export function PwaBoot() {
  const [installPromptEvent, setInstallPromptEvent] =
    useState<BeforeInstallPromptEvent | null>(null);
  const [dismissed, setDismissed] = useState(false);

  useEffect(() => {
    if (!("serviceWorker" in navigator)) {
      return;
    }

    navigator.serviceWorker.register("/sw.js").catch(() => undefined);
  }, []);

  useEffect(() => {
    const handleBeforeInstallPrompt = (event: Event) => {
      event.preventDefault();
      setInstallPromptEvent(event as BeforeInstallPromptEvent);
    };

    window.addEventListener("beforeinstallprompt", handleBeforeInstallPrompt);

    return () => {
      window.removeEventListener("beforeinstallprompt", handleBeforeInstallPrompt);
    };
  }, []);

  if (!installPromptEvent || dismissed) {
    return null;
  }

  return (
    <div className="install-pill">
      <div>
        <p className="install-pill-title">Install Pulse</p>
        <p className="install-pill-copy">Open it like an app from your home screen.</p>
      </div>
      <div className="install-pill-actions">
        <button
          className="install-pill-dismiss"
          onClick={() => setDismissed(true)}
          type="button"
        >
          Not now
        </button>
        <button
          className="install-pill-button"
          onClick={async () => {
            await installPromptEvent.prompt();
            const choice = await installPromptEvent.userChoice;

            if (choice.outcome === "accepted") {
              setInstallPromptEvent(null);
            } else {
              setDismissed(true);
            }
          }}
          type="button"
        >
          Install
        </button>
      </div>
    </div>
  );
}
