# satisfactory-server-aws-docker

Automated deployment of a Satisfactory dedicated server on AWS EC2 via AWS CDK (TypeScript).

The server installs via SteamCMD on an Ubuntu 22.04 instance, syncs save files to/from S3, and shuts itself down after 30 minutes of no players to keep costs low.

## Architecture

- **EC2** (`r6a.large` by default — 2 vCPU / 16 GB RAM) running Satisfactory as a systemd service
- **S3 bucket** for save file backups (synced every 5 min, restored on startup)
- **Lambda + API Gateway** REST endpoint to remotely start a stopped server
- **SSM** access via AWS Session Manager — no SSH key required

## Prerequisites

- [Node.js](https://nodejs.org/) 20+
- AWS CLI configured (`~/.aws/credentials` with a `[default]` profile)
- IAM user with sufficient permissions (EC2, S3, Lambda, IAM, CloudFormation, API Gateway)
- EC2 vCPU quota of at least 2 for Memory Optimized instances in your region

## Setup

### 1. Install dependencies

```sh
npm install
```

### 2. Create your config file

```sh
cp server-hosting/config.sample.ts server-hosting/config.ts
```

Edit `server-hosting/config.ts` — the two required fields are `account` and `region`:

```ts
export const Config = {
  region: 'us-east-1',
  account: '123456789012',   // your 12-digit AWS account ID
  prefix: 'SatisfactoryHosting',
  restartApi: true,
  useExperimentalBuild: false,
  bucketName: '',            // leave empty to auto-create, or name an existing bucket
  vpcId: '',
  subnetId: '',
  availabilityZone: '',
};
```

> `config.ts` is gitignored — never commit it.

### 3. Bootstrap CDK (first deploy only)

```sh
npx cdk bootstrap aws://YOUR_ACCOUNT_ID/YOUR_REGION
```

### 4. (Optional) Pre-load a save file

```sh
aws s3 mb s3://your-bucket-name
aws s3 cp /path/to/your/save.sav s3://your-bucket-name/server/save.sav
```

Set `bucketName` in `config.ts` to match, then deploy.

### 5. Deploy

```sh
npx cdk deploy
```

The stack takes ~4 minutes. After it completes, the EC2 instance installs Satisfactory in the background (~12 GB download). **Wait 10–15 minutes before connecting.**

## Connecting

Find your server's public IP in the EC2 console, then in Satisfactory:

**Main menu → Server Manager → Add Server → `<IP>:7777`**

### Required ports

The CDK stack opens these automatically; listed here for reference:

| Port | Protocol | Purpose |
|------|----------|---------|
| 7777 | UDP | Gameplay traffic |
| 7777 | TCP | Server API / Server Manager |
| 8888 | TCP | ReliableMessaging stream (join / state sync) |
| 15000 | UDP | Beacon |
| 15777 | UDP | Query |

> **Note:** TCP 8888 is easy to miss. Without it you can claim the server and load a
> save, but joining fails with **"connection to host lost"** after ~20 seconds, because
> the join-time state transfer runs over a separate TCP socket on 8888.

## Restarting the server

When the server auto-shuts down after idle, start it again via the API endpoint printed at the end of `cdk deploy`:

```sh
curl https://<api-id>.execute-api.<region>.amazonaws.com/prod/
```

## Cost estimate

`r6a.large` costs ~$0.1134/hr. With the 30-minute auto-shutdown, a 3-hour session costs roughly **$0.35**. S3 saves cost cents per month.

## Instance type

Change `instanceType` in [server-hosting/server-hosting-stack.ts](server-hosting/server-hosting-stack.ts) and redeploy to switch. The `r6a.large` (16 GB RAM) handles large factories well; drop to `t3.large` for lower cost on smaller worlds.

## Teardown

```sh
npx cdk destroy
```

The S3 saves bucket is **not** deleted automatically — remove it from the AWS console manually if needed.
