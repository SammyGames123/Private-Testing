"use client";

import Link from "next/link";
import { useEffect, useState } from "react";

function buildAppCallbackUrl() {
  if (typeof window === "undefined") {
    return "spilltop://auth/confirm";
  }

  return `spilltop://auth/confirm${window.location.search}${window.location.hash}`;
}

function readCallbackValue(name: string) {
  if (typeof window === "undefined") {
    return null;
  }

  const currentUrl = new URL(window.location.href);
  const queryMatch = currentUrl.searchParams.get(name);
  if (queryMatch) {
    return queryMatch;
  }

  const hashParams = new URLSearchParams(currentUrl.hash.replace(/^#/, ""));
  return hashParams.get(name);
}

export default function ConfirmAccountPage() {
  const [statusText, setStatusText] = useState("Your account has been confirmed.");
  const [hasAttemptedOpen, setHasAttemptedOpen] = useState(false);

  useEffect(() => {
    const errorDescription = readCallbackValue("error_description");
    if (errorDescription) {
      setStatusText(errorDescription);
      return;
    }

    const appCallbackUrl = buildAppCallbackUrl();
    const timer = window.setTimeout(() => {
      setHasAttemptedOpen(true);
      window.location.replace(appCallbackUrl);
    }, 450);

    return () => window.clearTimeout(timer);
  }, []);

  const appCallbackUrl = buildAppCallbackUrl();

  return (
    <main className="auth-shell auth-shell-branded auth-shell-confirm">
      <div className="auth-card auth-card-branded auth-card-compact auth-card-confirm">
        <div className="auth-confirm-emblem" aria-hidden="true">
          <div className="auth-confirm-emblem-ring">
            <span className="auth-confirm-emblem-core" />
          </div>
        </div>
        <p className="auth-logo auth-logo-confirm">Spilltop</p>
        <h1>Account confirmed</h1>
        <p className="auth-subtitle auth-handoff-note">
          {statusText}
        </p>
        <p className="auth-subtitle auth-handoff-note">
          Opening the app now{hasAttemptedOpen ? "." : "…"}
        </p>

        <div className="auth-handoff-actions">
          <a className="auth-submit auth-submit-link auth-submit-confirm" href={appCallbackUrl}>
            Open Spilltop
          </a>
          <p className="auth-footer auth-footer-compact">
            If you are on another device, head back to the Spilltop app and sign
            in there instead.
          </p>
          <p className="auth-footer auth-footer-compact">
            Need the web login instead? <Link href="/auth/login">Sign in here</Link>
          </p>
        </div>
      </div>
    </main>
  );
}
