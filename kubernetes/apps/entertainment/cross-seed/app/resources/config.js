// Note: Cross-Seed vars should be escaped with $${VAR_NAME} to avoid interpolation by Flux
module.exports = {
  delay: 20,
  qbittorrentUrl: "http://qbittorrent.entertainment.svc.cluster.local",
  torznab: [
    `http://prowlarr.entertainment.svc.cluster.local/49/api?apikey=$${process.env.PROWLARR_API_KEY}`, // atr
    `http://prowlarr.entertainment.svc.cluster.local/47/api?apikey=$${process.env.PROWLARR_API_KEY}`, // ar
    `http://prowlarr.entertainment.svc.cluster.local/48/api?apikey=$${process.env.PROWLARR_API_KEY}`, // ant
    `http://prowlarr.entertainment.svc.cluster.local/2/api?apikey=$${process.env.PROWLARR_API_KEY}`,  // avz
    `http://prowlarr.entertainment.svc.cluster.local/45/api?apikey=$${process.env.PROWLARR_API_KEY}`, // bhd
    `http://prowlarr.entertainment.svc.cluster.local/21/api?apikey=$${process.env.PROWLARR_API_KEY}`, // blu
    `http://prowlarr.entertainment.svc.cluster.local/11/api?apikey=$${process.env.PROWLARR_API_KEY}`, // btn
    `http://prowlarr.entertainment.svc.cluster.local/1/api?apikey=$${process.env.PROWLARR_API_KEY}`,  // fl
    `http://prowlarr.entertainment.svc.cluster.local/39/api?apikey=$${process.env.PROWLARR_API_KEY}`, // hds
    `http://prowlarr.entertainment.svc.cluster.local/44/api?apikey=$${process.env.PROWLARR_API_KEY}`, // hdt
    `http://prowlarr.entertainment.svc.cluster.local/38/api?apikey=$${process.env.PROWLARR_API_KEY}`, // ipt
    `http://prowlarr.entertainment.svc.cluster.local/26/api?apikey=$${process.env.PROWLARR_API_KEY}`, // mtv
    `http://prowlarr.entertainment.svc.cluster.local/84/api?apikey=$${process.env.PROWLARR_API_KEY}`, // nbl
    `http://prowlarr.entertainment.svc.cluster.local/8/api?apikey=$${process.env.PROWLARR_API_KEY}`,  // ptp
    `http://prowlarr.entertainment.svc.cluster.local/42/api?apikey=$${process.env.PROWLARR_API_KEY}`, // phd
    `http://prowlarr.entertainment.svc.cluster.local/6/api?apikey=$${process.env.PROWLARR_API_KEY}`,  // st
    `http://prowlarr.entertainment.svc.cluster.local/46/api?apikey=$${process.env.PROWLARR_API_KEY}`, // td
    `http://prowlarr.entertainment.svc.cluster.local/41/api?apikey=$${process.env.PROWLARR_API_KEY}`, // ts
    `http://prowlarr.entertainment.svc.cluster.local/20/api?apikey=$${process.env.PROWLARR_API_KEY}`, // tl
    `http://prowlarr.entertainment.svc.cluster.local/40/api?apikey=$${process.env.PROWLARR_API_KEY}`, // uhdb
  ],
  port: process.env.CROSSSEED_PORT || 80,
  apiAuth: false,
  action: "inject",
  includeEpisodes: false,
  includeSingleEpisodes: true,
  includeNonVideos: true,
  duplicateCategories: true,
  matchMode: "safe",
  skipRecheck: true,
  linkType: "hardlink",
  linkDir: "/media/Downloads/qbittorrent/complete/cross-seed",
  dataDirs: [
    "/media/Downloads/qbittorrent/complete/prowlarr",
    "/media/Downloads/qbittorrent/complete/radarr",
    "/media/Downloads/qbittorrent/complete/sonarr",
  ],
  maxDataDepth: 1,
  outputDir: "/config/xseeds",
  torrentDir: "/config/qBittorrent/BT_backup",
};
