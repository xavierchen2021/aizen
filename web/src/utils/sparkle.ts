export interface VersionInfo {
  version: string;
  downloadUrl: string;
}

interface SparkleReleaseCandidate {
  versionKey: string | null;
  displayVersion: string;
  downloadUrl: string;
  pubDate: number | null;
}

const tokenizeVersion = (version: string) =>
  version
    .split(/[\.-]/)
    .map((segment) => segment.trim())
    .filter((segment) => segment.length > 0)
    .map((segment) =>
      /^\d+$/.test(segment)
        ? { type: "number" as const, value: parseInt(segment, 10) }
        : { type: "string" as const, value: segment.toLowerCase() }
    );

const compareVersionStrings = (a: string, b: string): number => {
  const tokensA = tokenizeVersion(a);
  const tokensB = tokenizeVersion(b);
  const maxLength = Math.max(tokensA.length, tokensB.length);

  for (let index = 0; index < maxLength; index += 1) {
    const segA = tokensA[index] ?? { type: "number" as const, value: 0 };
    const segB = tokensB[index] ?? { type: "number" as const, value: 0 };

    if (segA.type === segB.type) {
      if (segA.value === segB.value) continue;
      return segA.value > segB.value ? 1 : -1;
    }

    if (segA.type === "number" && segB.type === "string") return 1;
    if (segA.type === "string" && segB.type === "number") return -1;
  }

  return 0;
};

export const findLatestSparkleRelease = (xml: Document): VersionInfo | null => {
  const items = Array.from(xml.querySelectorAll("channel > item"));
  let latest: SparkleReleaseCandidate | null = null;

  for (const item of items) {
    const enclosure = item.querySelector("enclosure");
    if (!enclosure) continue;

    const downloadUrl = enclosure.getAttribute("url")?.trim();
    if (!downloadUrl) continue;

    const versionAttr = enclosure.getAttribute("sparkle:version")?.trim() ?? "";
    const shortVersion = enclosure.getAttribute("sparkle:shortVersionString")?.trim() ?? "";
    const versionKey = versionAttr || shortVersion || null;
    const displayVersion = shortVersion || versionAttr || "";
    const pubDateText = item.querySelector("pubDate")?.textContent?.trim() ?? "";
    const parsedPubDate = pubDateText ? Date.parse(pubDateText) : NaN;

    const candidate: SparkleReleaseCandidate = {
      versionKey,
      displayVersion,
      downloadUrl,
      pubDate: Number.isNaN(parsedPubDate) ? null : parsedPubDate,
    };

    if (!latest) {
      latest = candidate;
      continue;
    }

    if (candidate.versionKey && latest.versionKey) {
      const versionComparison = compareVersionStrings(candidate.versionKey, latest.versionKey);
      if (versionComparison > 0) {
        latest = candidate;
        continue;
      }
      if (versionComparison < 0) continue;
    } else if (candidate.versionKey && !latest.versionKey) {
      latest = candidate;
      continue;
    } else if (!candidate.versionKey && latest.versionKey) {
      continue;
    }

    const latestPubDate = latest.pubDate ?? -Infinity;
    const candidatePubDate = candidate.pubDate ?? -Infinity;

    if (candidatePubDate > latestPubDate) {
      latest = candidate;
    }
  }

  if (!latest) return null;

  return {
    version: latest.displayVersion,
    downloadUrl: latest.downloadUrl,
  };
};

export const fetchLatestVersion = async (): Promise<VersionInfo | null> => {
  try {
    const res = await fetch("https://r2.aizen.win/appcast.xml");
    const xmlText = await res.text();
    const parser = new DOMParser();
    const xml = parser.parseFromString(xmlText, "text/xml");
    return findLatestSparkleRelease(xml);
  } catch {
    return null;
  }
};
