# Plane Deployment Preparation Questions

1. **Chart Version Confirmation**  
   Do you want to deploy Plane with the Helm chart version that matches the v1.0.0 image set, or is there a different chart release you’d prefer to pin in the HelmRelease?

   _Answer:_

2. **Database Configuration Details**  
   For CloudNativePG, which database names and user accounts should each Plane service (backend, space, admin, live) use? If you plan to reuse a single database/user, spell that out explicitly. Include the 1Password field names (e.g., `PLANE_DB_PASSWORD`) that will hold each credential.

   _Answer:_

3. **Redis Configuration**  
   Should Plane share the existing Dragonfly instance without authentication, or will you supply a password? List the connection string format you expect Plane to use and the matching 1Password field name(s).

   _Answer:_

4. **Object Storage Settings**  
   Provide the rook-ceph S3 endpoint URL, bucket name, and any region/SSL parameters Plane requires. Specify which 1Password fields (e.g., `PLANE_S3_ACCESS_KEY`, `PLANE_S3_SECRET_KEY`) will store the credentials.

   _Answer:_

5. **Ingress Requirements**  
   Confirm the external hostname (default `plane.${SECRET_DOMAIN}`), the ingress class (`external`), and any annotations (e.g., external-dns, auth middleware, rate limits) you need applied to the ingress resource.

   _Answer:_

6. **Persistent Storage Expectations**  
   Identify which Plane components need persistent volumes, the desired capacity for each (defaulting to 20 Gi if you are unsure), and the storage class to use. Note whether each PVC should be managed through the VolSync template.

   _Answer:_

7. **Environment & Feature Flags**  
   List any additional Plane configuration flags, feature toggles, SMTP settings, or OIDC details (client IDs, issuer URLs, redirect URIs). Provide the exact 1Password field names you’ll populate for each value (e.g., `PLANE_SMTP_HOST`).

   _Answer:_

8. **Resource Requests and Limits**  
   Do you have target CPU/memory requests or limits for Plane services? If not, confirm that we should start with conservative defaults and adjust after initial deployment.

   _Answer:_

9. **Observability & Integrations**  
   Are there specific annotations or sidecars needed for Prometheus scraping, Loki logs, or other monitoring tools beyond the cluster defaults?

   _Answer:_

10. **Deployment Dependencies**  
    Confirm any HelmRelease `dependsOn` requirements (e.g., rook-ceph, volsync, cnpg) so Flux applies Plane after all prerequisites are ready.

   _Answer:_
