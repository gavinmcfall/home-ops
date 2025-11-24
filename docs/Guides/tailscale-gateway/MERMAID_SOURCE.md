# Network Architecture Diagram - Mermaid Source

This is the Mermaid source code for the network architecture diagram. For the best viewing experience, copy this code and paste it into [Eraser.io](https://app.eraser.io/).

```mermaid
flowchart LR
    subgraph Users["Users"]
        PubUser[Public User]
        LANUser[LAN User]
        VPNUser[VPN User]
    end

    subgraph Entry["Entry Points"]
        direction TB
        CFEdge[Cloudflare Edge]
        TSDNS[Tailscale MagicDNS]
    end

    subgraph Cluster["Kubernetes Cluster"]
        direction TB

        CFD[Cloudflared QUIC Tunnel]
        K8sGW[k8s-gateway 10.90.3.200]

        subgraph Gateways["Gateway Layer - Envoy"]
            direction TB
            ExtGW[External Gateway<br/>10.90.3.201]
            IntGW[Internal Gateway<br/>10.90.3.202]
            TSGW[Tailscale Gateway<br/>gateway.ts.net]
        end

        subgraph Auth["Authentication"]
            direction LR
            OAuth2[OAuth2-Proxy] --> PocketID[PocketID OIDC]
        end
    end

    subgraph Services["Application Services"]
        direction TB
        ExtSvc[External-Only Services]
        IntSvc[Internal-Only Services]
        DualSvc[Dual Access Services]
    end

    subgraph Management["DNS Management & Foundation"]
        direction TB
        ExtDNS[external-dns Cloudflare]
        ExtDNSUnifi[external-dns-unifi]
        Cilium[Cilium LoadBalancer 10.90.3.200-210]
        TSOp[Tailscale Operator]
    end

    subgraph External["External Systems"]
        direction TB
        CFDNS[Cloudflare DNS API]
        UniFi[UniFi UDM-Pro 10.90.254.1]
    end

    %% User traffic flows
    PubUser --> CFEdge
    LANUser --> K8sGW
    VPNUser --> TSDNS

    %% Entry to cluster
    CFEdge --> CFD
    TSDNS --> K8sGW

    %% Cluster routing
    CFD --> ExtGW
    K8sGW --> IntGW
    K8sGW --> TSGW

    %% Authentication
    ExtGW --> OAuth2
    IntGW -.optional.-> PocketID

    %% Service routing
    ExtGW --> ExtSvc
    IntGW --> IntSvc
    IntGW --> DualSvc
    TSGW --> DualSvc

    %% DNS management
    ExtDNS -.watches.-> K8sGW
    ExtDNS ==> CFDNS
    ExtDNSUnifi -.watches.-> K8sGW
    ExtDNSUnifi ==> UniFi

    %% Foundation
    Cilium -.IPAM.-> ExtGW
    Cilium -.IPAM.-> IntGW
    Cilium -.IPAM.-> K8sGW
    TSOp -.LoadBalancer.-> TSGW

    classDef users fill:#ffdddd,stroke:#cc0000,color:#000,stroke-width:2px
    classDef entry fill:#ffe6cc,stroke:#ff8800,color:#000,stroke-width:2px
    classDef cluster fill:#e6e6e6,stroke:#666666,color:#000,stroke-width:2px
    classDef gateway fill:#ffe6cc,stroke:#ff8800,color:#000,stroke-width:3px
    classDef auth fill:#d4f1d4,stroke:#00aa00,color:#000,stroke-width:2px
    classDef service fill:#e6e6ff,stroke:#6666cc,color:#000,stroke-width:2px
    classDef dns fill:#cce6ff,stroke:#0066cc,color:#000,stroke-width:2px
    classDef infra fill:#e6e6e6,stroke:#666666,color:#000,stroke-width:2px
    classDef external fill:#fff4cc,stroke:#cc9900,color:#000,stroke-width:2px

    class PubUser,LANUser,VPNUser users
    class CFEdge,TSDNS entry
    class ExtGW,IntGW,TSGW gateway
    class OAuth2,PocketID auth
    class ExtSvc,IntSvc,DualSvc service
    class K8sGW,ExtDNS,ExtDNSUnifi dns
    class CFD,Cilium,TSOp infra
    class CFDNS,UniFi external

    %% Make subgraph backgrounds transparent with high contrast titles
    style Users fill:none,stroke:#999,color:#eee
    style Entry fill:none,stroke:#999,color:#eee
    style External fill:none,stroke:#999,color:#eee
    style Cluster fill:none,stroke:#999,color:#eee
    style Services fill:none,stroke:#999,color:#eee
    style Management fill:none,stroke:#999,color:#eee
    style Gateways fill:none,stroke:#999,color:#eee
    style Auth fill:none,stroke:#999,color:#eee
```
