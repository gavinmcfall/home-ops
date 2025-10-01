# Plane Deployment Preparation Questions

1. **Chart Version Confirmation**
   Do you want to deploy Plane with the Helm chart version that matches the v1.0.0 image set, or is there a different chart release you’d prefer to pin in the HelmRelease?

   _Answer:_
    artifacts.plane.so/makeplane/plane-frontend:v1.0.0
    sha256:a07fcc32cf45b1cb5cc7397d86d061f524194c535dec0135741fafdfc3f8c376

    artifacts.plane.so/makeplane/plane-space:v1.0.0
    sha256:9ce65d871f9afe08e236e14c6c97f5391ea23176cce5dce2fba25ef0019129e4

    digest artifacts.plane.so/makeplane/plane-admin:v1.0.0
    sha256:013d88c838a7d085e3424a210ceecb2a2a8d37bebd023bf571618b8bc0797a01

    artifacts.plane.so/makeplane/plane-live:v1.0.0
    sha256:d4ee8314c7946357110bcb3c62ad69186f9b12253f670e2ab10c6a84d99b4772

    artifacts.plane.so/makeplane/plane-backend:v1.0.0
    sha256:c1492e1437a07877955052bf2da645ca90dd6e0a0bc97ac8bd0efbc34616aca1

2. **Database Configuration Details**
   For CloudNativePG, which database names and user accounts should each Plane service (backend, space, admin, live) use? If you plan to reuse a single database/user, spell that out explicitly. Include the 1Password field names (e.g., `PLANE_DB_PASSWORD`) that will hold each credential.

   _Answer:_
   lets use an init DB approach like I do for Sonarr
   I will specify the initdb credentials etc like in Sonarr for the databases (if it needs multiple then handle that) It'll be a single user for them all

3. **Redis Configuration**
   Should Plane share the existing Dragonfly instance without authentication, or will you supply a password? List the connection string format you expect Plane to use and the matching 1Password field name(s).

   _Answer:_
   yes, same instance without auth is fine.
   planes values.yaml shows only a single Redis ENV VAR "remote_redis_url"
   So the string should be "redis://dragonfly.database.svc.cluster.local:6379"

4. **Object Storage Settings**
   Provide the rook-ceph S3 endpoint URL, bucket name, and any region/SSL parameters Plane requires. Specify which 1Password fields (e.g., `PLANE_S3_ACCESS_KEY`, `PLANE_S3_SECRET_KEY`) will store the credentials.

   _Answer:_
  aws_access_key: ''
  aws_secret_access_key: ''
  aws_region: ''
  aws_s3_endpoint_url: ''

  Can be found in the rook-ceph entry in 1password and are called

  ROOK_AWS_ACCESS_KEY
  ROOK_AWS_SECRET_ACCESS_KEY
  ROOK_AWS_S3_ENDPOINT
  ROOK_AWS_S3_REGION

5. **Ingress Requirements**
   Confirm the external hostname (default `plane.${SECRET_DOMAIN}`), the ingress class (`external`), and any annotations (e.g., external-dns, auth middleware, rate limits) you need applied to the ingress resource.

   _Answer:_
   plane.${SECRET_DOMAIN} is fine

6. **Persistent Storage Expectations**
   Identify which Plane components need persistent volumes, the desired capacity for each (defaulting to 20 Gi if you are unsure), and the storage class to use. Note whether each PVC should be managed through the VolSync template.

   _Answer:_

   minios storage can be set to 20Gi
   I dont believe Plane has any other PVC needs outside of Postgres/Redis and S3

7. **Environment & Feature Flags**
   List any additional Plane configuration flags, feature toggles, SMTP settings, or OIDC details (client IDs, issuer URLs, redirect URIs). Provide the exact 1Password field names you’ll populate for each value (e.g., `PLANE_SMTP_HOST`).

   _Answer:_
   I dont know what I might want here. Why don't you review the env vars and suggest things I might want to turn off or on and any values I need to set. Note any secrets MUST be put into the externalsecrets.yaml

8. **Resource Requests and Limits**
   Do you have target CPU/memory requests or limits for Plane services? If not, confirm that we should start with conservative defaults and adjust after initial deployment.

   _Answer:_
   Use the defaults that are specified in the values.yaml but actually put them in the help release so they are easy to adjust later

9. **Observability & Integrations**
   Are there specific annotations or sidecars needed for Prometheus scraping, Loki logs, or other monitoring tools beyond the cluster defaults?

   _Answer:_
   nothing specific at this point

10. **Deployment Dependencies**
    Confirm any HelmRelease `dependsOn` requirements (e.g., rook-ceph, volsync, cnpg) so Flux applies Plane after all prerequisites are ready.

   _Answer:_
   ks.yaml should have the kustomization depends on for
   cluster-apps-rook-ceph-cluster
   dragonfly-cluster
   cloudnative-pg-cluster17

