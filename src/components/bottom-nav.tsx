"use client";

import Link from "next/link";
import { usePathname, useSearchParams } from "next/navigation";
import type { ReactNode } from "react";

type NavItem = {
  label: string;
  href: string;
  isActive: (pathname: string, searchParams: URLSearchParams) => boolean;
  icon: ReactNode;
};

function HomeIcon() {
  return (
    <svg aria-hidden="true" fill="none" height="22" viewBox="0 0 24 24" width="22">
      <path
        d="M4 10.5 12 4l8 6.5V20a1 1 0 0 1-1 1h-4.5v-6h-5v6H5a1 1 0 0 1-1-1z"
        stroke="currentColor"
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeWidth="1.8"
      />
    </svg>
  );
}

function FollowingIcon() {
  return (
    <svg aria-hidden="true" fill="none" height="22" viewBox="0 0 24 24" width="22">
      <path
        d="M9 12a3 3 0 1 0 0-6 3 3 0 0 0 0 6Zm6 1a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5Z"
        stroke="currentColor"
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeWidth="1.8"
      />
      <path
        d="M4 20a5 5 0 0 1 10 0M13 20a4 4 0 0 1 7 0"
        stroke="currentColor"
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeWidth="1.8"
      />
    </svg>
  );
}

function UploadIcon() {
  return (
    <svg aria-hidden="true" fill="none" height="22" viewBox="0 0 24 24" width="22">
      <path
        d="M12 5v14M5 12h14"
        stroke="currentColor"
        strokeLinecap="round"
        strokeWidth="1.8"
      />
      <rect
        height="18"
        rx="5"
        stroke="currentColor"
        strokeWidth="1.8"
        width="18"
        x="3"
        y="3"
      />
    </svg>
  );
}

function InboxIcon() {
  return (
    <svg aria-hidden="true" fill="none" height="22" viewBox="0 0 24 24" width="22">
      <path
        d="M5 7.5A2.5 2.5 0 0 1 7.5 5h9A2.5 2.5 0 0 1 19 7.5v9a2.5 2.5 0 0 1-2.5 2.5h-9A2.5 2.5 0 0 1 5 16.5z"
        stroke="currentColor"
        strokeWidth="1.8"
      />
      <path
        d="m7 9 5 4 5-4"
        stroke="currentColor"
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeWidth="1.8"
      />
    </svg>
  );
}

function ProfileIcon() {
  return (
    <svg aria-hidden="true" fill="none" height="22" viewBox="0 0 24 24" width="22">
      <path
        d="M12 12a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7Z"
        stroke="currentColor"
        strokeWidth="1.8"
      />
      <path
        d="M5 20a7 7 0 0 1 14 0"
        stroke="currentColor"
        strokeLinecap="round"
        strokeWidth="1.8"
      />
    </svg>
  );
}

const navItems: NavItem[] = [
  {
    label: "Home",
    href: "/feed",
    isActive: (pathname, searchParams) =>
      pathname === "/feed" && searchParams.get("tab") !== "following",
    icon: <HomeIcon />,
  },
  {
    label: "Following",
    href: "/feed?tab=following",
    isActive: (pathname, searchParams) =>
      pathname === "/feed" && searchParams.get("tab") === "following",
    icon: <FollowingIcon />,
  },
  {
    label: "Upload",
    href: "/videos/new/camera",
    isActive: (pathname) =>
      pathname === "/videos/new" || pathname.startsWith("/videos/new/"),
    icon: <UploadIcon />,
  },
  {
    label: "Inbox",
    href: "/messages",
    isActive: (pathname) => pathname === "/messages",
    icon: <InboxIcon />,
  },
  {
    label: "Profile",
    href: "/dashboard",
    isActive: (pathname) => pathname === "/dashboard" || pathname === "/profile",
    icon: <ProfileIcon />,
  },
];

export function BottomNav() {
  const pathname = usePathname();
  const searchParams = useSearchParams();

  if (
    pathname.startsWith("/admin") ||
    pathname.startsWith("/auth") ||
    pathname.startsWith("/videos/new/camera")
  ) {
    return null;
  }

  return (
    <nav aria-label="Primary" className="bottom-nav">
      {navItems.map((item) => {
        const active = item.isActive(pathname, searchParams);

        return (
          <Link
            className={active ? "bottom-nav-item active" : "bottom-nav-item"}
            href={item.href}
            key={item.label}
          >
            <span className="bottom-nav-icon">{item.icon}</span>
            <span className="bottom-nav-label">{item.label}</span>
          </Link>
        );
      })}
    </nav>
  );
}
