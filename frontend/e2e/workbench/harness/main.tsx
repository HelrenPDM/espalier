import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import "./harness.css";
import { Harness } from "./Harness";

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <Harness />
  </StrictMode>,
);
