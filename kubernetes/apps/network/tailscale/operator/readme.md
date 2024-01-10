# Setting up the Tailscale Operator

> [!IMPORTANT]
> I set this up so I have a way to remotely manage my cluster. I am not using Tailscale for anything else
> My setup is using app template, not the official helmchart
> My setup is using a 1password connect server for external secret storage, yours might be different. Adjustments may need to be made
> Ensure you have a tailscale account setup. You only need the free one
> Setup the tailscale app on at least two devices (phone, laptop, etc)

## Tailscale Account Setup

We are going to start on [tailscale.com](https://login.tailscale.com/)

1. Login to Tailscale
2. Click on the [Access controls](https://login.tailscale.com/admin/acls/file) tab
3. Look for the section called: `// Define the tags which can be applied to devices and by which users.``
4. Edit this section to look like this:
    ```
        "tagOwners": {
            "tag:k8s-operator": [],
            "tag:k8s":          ["tag:k8s-operator"],
        },
    ```
5. Ensure you click **Save**
6. Next, click [DNS](https://login.tailscale.com/admin/dns) and scroll down to **MagicDNS** 
7. Select **Settings** from the top meny and click on [OAuth Clients](https://login.tailscale.com/admin/settings/oauth)
8. Click the button on the right called: **Generate OAuth client...**
9. Set the following settings
    - Description: Anything you like
    - Device:
        - Read: :white_check_mark:
        - Write: :white_check_mark:
    - Click **Add tags** and select `k8s-operator`
    - <img src="https://raw.githubusercontent.com/gavinmcfall/home-ops/main/docs/src/assets/Tailscale_01.png"/>
10. Click `Generate client`
11. You will be presented with:
    - Client ID
    - Secret
12. Open up one password and go into the vault you have configured for your kubernetes external secret stores
13. Create a new password entry and call it `tailscale`
14. Add two new password fields called:
    - `TAILSCALE_OATH_CLIENT_ID`
    - `TAILSCALE_OAUTH_CLIENT_SECRET`
15. Copy the `Client ID` and `Secret` from Tailscale into these fields and save
16. Back in Tailscale, go to **Settings** then [Device management](https://login.tailscale.com/admin/settings/device-management)
17. Follow the provided [Tailscale guide](https://tailscale.com/kb/1226/tailnet-lock) to setup **Tailnet lock**
18. Now you can copy the files from this repo into your own kubernetes cluster
19. Ensure you add `  - ./tailscale/ks.yaml` to your root `kustomization.yaml` for that namespace
    > [!IMPORTANT]
    > Comment out the line you added for right now. This way you can commit to git as you go along without fear of it installing before you are ready
20. If you built your cluster using the [Flux Cluster Template](https://github.com/onedr0p/flux-cluster-template) you are going to want to go to your CLI and run the following:
    ```
    sops ~/<path to your repo>/kubernetes/flux/vars/cluster-secrets.sops.yaml
    ```
21. Add another variable in here called `TAILSCALE_EMAIL` and set it to the email address used in your Tailscale Account
22. Push your changes to git :ferry:
23. Verify that your changes are safely in git and then uncomment out the line from setp 19
24. Watch your cluster and see the files roll out. **NOTE**: This won't be working just yet
25. Once your pod is up and running you need to go back into Tailscales Web Dashboard
26. In the top menu click on [Machines](https://login.tailscale.com/admin/machines)
27. You should see the `tailscale operator` listed. Click on it's name
28. Click **Sign Node** and follow the prompts to sign the node
29. Back in the CLI. Run the following command: `tailscale configure kubeconfig tailscale-operator`
30. A new KUBECONFIG will have been added to the path `~/.kube/config` You will need to copy the contents of that into your KUBECONFIG (where ever you store that)
31. You can now execute `Kubectl` against your remote cluster


