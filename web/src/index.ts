import { serve } from "bun";
import index from "./index.html";

const server = serve({
  port: 8787,
  routes: {
    "/": index,
    "/robots.txt": Bun.file("./src/robots.txt"),
    "/sitemap.xml": Bun.file("./src/sitemap.xml"),
  },

  development: process.env.NODE_ENV !== "production" && {
    hmr: true,
    console: true,
  },
});

console.log(`Server running at ${server.url}`);
