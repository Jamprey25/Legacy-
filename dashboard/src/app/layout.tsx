import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Legacy — Task Dashboard",
  description: "Build tracker for Legacy iOS app",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
