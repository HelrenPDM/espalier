import { QueryClientProvider } from "@tanstack/react-query";
import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { RouterProvider } from "react-router/dom";
import "./styles/app.css";
import "./i18n";
import { queryClient } from "./api/queryClient";
import { productName } from "./app/product";
import { createAppRouter } from "./app/router";
import { applyTheme, followSystemTheme } from "./app/theme";

// index.html holds no inline script (CSP `script-src 'self'`), so the theme
// is applied here, before the first render.
applyTheme();
followSystemTheme();
document.title = productName;

const router = createAppRouter();

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <QueryClientProvider client={queryClient}>
      <RouterProvider router={router} />
    </QueryClientProvider>
  </StrictMode>,
);
