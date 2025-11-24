# Plane Community Chart Follow-Up Questions

1. **Helm Chart Version**
   Which chart release from `https://helm.plane.so` should we pin for the community edition deployment? Please provide the exact version string (e.g., `plane-0.x.y`).

   https://github.com/makeplane/helm-charts/releases
   Shows latest Community Edition is https://github.com/makeplane/helm-charts/releases/tag/plane-ce-1.2.2

2. **Remote Postgres Details**
   Confirm the database name the Plane stack should initialize inside CNPG and the username we should expose to the chart (defaults are `plane`). List the 1Password fields (e.g., `PLANE_PG_USER`, `PLANE_PG_PASSWORD`) so we can template the ExternalSecret correctly.

   The DB name in the secret for plane should be *dbname as then the initdb will use the plane-secret to lookup the db name etc same as sonarr

3. **Postgres Connection URL**
   Plane’s values support `env.pgdb_remote_url`. Do you want to supply a full DSN (e.g., `postgres://user:pass@postgres17-rw.database.svc.cluster.local:5432/plane`) via secrets, or should we populate individual host/user/password env vars instead? If you prefer the DSN, specify the 1Password field name for it.

   Just like sonarr we will specify dburl, dbname, dbpass and dbuser for the init DB and then use yaml anchors for the plane secrets
   (Note the init DB will also need the postgres super pass as shown the sonarr externalsecret)

4. **RabbitMQ Strategy**
   Should we disable the bundled RabbitMQ (`rabbitmq.local_setup: false`) and point Plane at an existing broker, or keep the in-cluster RabbitMQ? If external, provide the connection URL and matching 1Password field name.

   I have mosquitto deployed in the database namespace. you can see the use of that in the home-assistant externalsecret in the home-automation name sapce

5. **Object Storage Bucket**
   You mentioned rook-ceph S3 credentials, but we still need the bucket name to set in `env.docstore_bucket`. What bucket name should we use, and do you want to keep the 5 MiB upload limit or adjust it?

   Lets specify the bucket name in the external secret like we do for the DB name

6. **Ingress Overrides**
   Confirm the desired ingress annotations for the `external` class (e.g., `external-dns.alpha.kubernetes.io/target`) and whether we should set `ssl.tls_secret_name` or leave certificate management to the cluster defaults.

   Example

       ingress:
      app:
        annotations:
          external-dns.alpha.kubernetes.io/target: external.${SECRET_DOMAIN}
        className: external
        hosts:
          - host: "{{ .Release.Name }}.${SECRET_DOMAIN}"
            paths:
              - path: /
                service:
                  identifier: app
                  port: http

7. **Public URLs & CORS**
   Provide values for `env.NEXT_PUBLIC_DEPLOY_URL`, `env.cors_allowed_origins`, and the public URL you expect end users to hit. Include the 1Password keys for any secrets embedded in these URLs if applicable.

   I dont know what these are give me more info. If this is external ingress then the URL on the web will be plane.${SECRET_DOMAIN}

8. **Admin & Notification Settings**
   Plane needs `env.instance_admin_email`; share the email address to configure. If you plan to enable SMTP later, note the relevant 1Password fields now so we leave placeholders in the ExternalSecret.

   looks like this is configured in the UI after deployment

9. **Runtime Secrets**
   The default chart supplies `env.secret_key`. Do you want us to generate new values (placeholder `PLANE_SECRET_KEY`) for `secret_key`, `live_server_secret_key`, and any other security-sensitive keys, or should we reuse the defaults temporarily?

   yes add vars into the external secret and add a comment on how to generate those keys/passwords via the CLI before storing them in 1password

10. **Optional Components**
    Components such as `worker`, `beatworker`, and extra env subsets (e.g., Sentry, live env) are enabled by default. Should we deploy them all on day one, or disable certain pieces (e.g., Sentry, live env) until credentials exist? Let us know which sections to comment out versus leave enabled with placeholders.

    Deploy evertyhing, ensure the secrets are properly added into the externalsecrets.yaml file for me to populate.
    Organise the secret file nicely
