# Jenkins + GitHub + Nginx Docker CI/CD Pipeline

## Architecture Overview

```
GitHub Repo → Webhook → Jenkins (Docker) → Build → Deploy Nginx (Docker)
```

---

## STEP 1: Run Jenkins on Docker

### 1.1 Create Docker Network (so Jenkins can talk to other containers)

```bash
docker network create jenkins-net
```

### 1.2 Create Jenkins Volume (persist data across restarts)

```bash
docker volume create jenkins-data
```

### 1.3 Run Jenkins Container

```bash
docker run -d \
  --name jenkins \
  --network jenkins-net \
  -p 8080:8080 \
  -p 50000:50000 \
  -v jenkins-data:/var/jenkins_home \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v $(which docker):/usr/bin/docker \
  --restart=unless-stopped \
  jenkins/jenkins:lts
```

> **Key flags explained:**
> - `-v /var/run/docker.sock:/var/run/docker.sock` → lets Jenkins run Docker commands (Docker-in-Docker)
> - `-v $(which docker):/usr/bin/docker` → mounts Docker binary into Jenkins
> - `-p 8080:8080` → Jenkins UI
> - `-p 50000:50000` → Agent communication

### 1.4 Fix Docker Socket Permissions inside Jenkins

```bash
docker exec -u root jenkins chmod 666 /var/run/docker.sock
```

### 1.5 Get Initial Admin Password

```bash
docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

### 1.6 Access Jenkins UI

Open: **http://localhost:8080**

- Paste the password from above
- Click **"Install suggested plugins"**
- Create your admin user

---

## STEP 2: Install Required Jenkins Plugins

Go to: **Manage Jenkins → Plugins → Available Plugins**

Install these:
- ✅ **Git Plugin**
- ✅ **GitHub Plugin**
- ✅ **GitHub Integration Plugin**
- ✅ **Pipeline**
- ✅ **Docker Pipeline**
- ✅ **Blue Ocean** (optional, better UI)

Restart Jenkins after installing.

---

## STEP 3: GitHub Repository Setup

### 3.1 Create your GitHub Repo

Create a repo (e.g., `nginx-jenkins-demo`) with this structure:

```
nginx-jenkins-demo/
├── Jenkinsfile
├── nginx/
│   ├── Dockerfile
│   └── html/
│       └── index.html
└── docker-compose.yml
```

### 3.2 Files to commit to your repo

**`nginx/Dockerfile`**
```dockerfile
FROM nginx:alpine
COPY html/ /usr/share/nginx/html/
EXPOSE 80
```

**`nginx/html/index.html`**
```html
<!DOCTYPE html>
<html>
<head><title>Deployed by Jenkins!</title></head>
<body>
  <h1>✅ Nginx deployed via Jenkins CI/CD</h1>
  <p>Build: #BUILD_NUMBER</p>
</body>
</html>
```

**`Jenkinsfile`** → (see Step 5 below)

---

## STEP 4: Configure GitHub Webhook

### 4.1 Expose Jenkins to the Internet (for webhooks)

If running locally, use **ngrok** to get a public URL:

```bash
# Install ngrok, then:
ngrok http 8080
# You'll get something like: https://abc123.ngrok.io
```

### 4.2 Add Webhook in GitHub

1. Go to your GitHub repo → **Settings → Webhooks → Add webhook**
2. Set:
   - **Payload URL**: `https://abc123.ngrok.io/github-webhook/`
   - **Content type**: `application/json`
   - **Events**: Select **"Just the push event"** (or "Let me select" → Push + Pull Request)
3. Click **Add webhook**

### 4.3 Create GitHub Personal Access Token (PAT)

1. GitHub → **Settings → Developer Settings → Personal Access Tokens → Tokens (classic)**
2. Generate token with scopes: `repo`, `admin:repo_hook`
3. **Copy the token** (shown only once!)

### 4.4 Add GitHub Credentials to Jenkins

1. Jenkins → **Manage Jenkins → Credentials → System → Global credentials**
2. Click **Add Credentials**:
   - **Kind**: Username with password
   - **Username**: your GitHub username
   - **Password**: your PAT token
   - **ID**: `github-credentials`
   - **Description**: GitHub PAT

---

## STEP 5: Create the Jenkins Pipeline

### 5.1 Jenkinsfile (commit this to your repo root)

```groovy
pipeline {
    agent any

    environment {
        IMAGE_NAME    = "nginx-app"
        CONTAINER_NAME = "nginx-deployed"
        HOST_PORT     = "8090"
        CONTAINER_PORT = "80"
    }

    triggers {
        githubPush()   // Trigger on GitHub push events
    }

    stages {

        stage('Checkout') {
            steps {
                echo "📥 Cloning repository..."
                checkout scm
            }
        }

        stage('Build Docker Image') {
            steps {
                echo "🔨 Building Nginx Docker image..."
                sh """
                    docker build \
                      -t ${IMAGE_NAME}:${BUILD_NUMBER} \
                      -t ${IMAGE_NAME}:latest \
                      ./nginx
                """
            }
        }

        stage('Test Image') {
            steps {
                echo "🧪 Testing the image..."
                sh """
                    docker run --rm -d \
                      --name nginx-test-${BUILD_NUMBER} \
                      -p 8099:80 \
                      ${IMAGE_NAME}:${BUILD_NUMBER}
                    
                    sleep 3
                    curl -f http://localhost:8099 || exit 1
                    docker stop nginx-test-${BUILD_NUMBER}
                    echo "✅ Test passed!"
                """
            }
        }

        stage('Deploy Nginx Container') {
            steps {
                echo "🚀 Deploying Nginx container..."
                sh """
                    # Stop & remove existing container (if any)
                    docker stop ${CONTAINER_NAME} 2>/dev/null || true
                    docker rm   ${CONTAINER_NAME} 2>/dev/null || true

                    # Run new container
                    docker run -d \
                      --name ${CONTAINER_NAME} \
                      --network jenkins-net \
                      -p ${HOST_PORT}:${CONTAINER_PORT} \
                      --restart unless-stopped \
                      ${IMAGE_NAME}:${BUILD_NUMBER}

                    echo "✅ Nginx deployed at http://localhost:${HOST_PORT}"
                """
            }
        }

        stage('Verify Deployment') {
            steps {
                echo "🔍 Verifying deployment..."
                sh """
                    sleep 3
                    curl -f http://localhost:${HOST_PORT} || exit 1
                    docker ps | grep ${CONTAINER_NAME}
                    echo "✅ Deployment verified!"
                """
            }
        }

        stage('Cleanup Old Images') {
            steps {
                echo "🧹 Cleaning up old Docker images..."
                sh "docker image prune -f"
            }
        }
    }

    post {
        success {
            echo """
            ╔══════════════════════════════════════╗
            ║   ✅  PIPELINE SUCCEEDED!             ║
            ║   Nginx running on port ${HOST_PORT}    ║
            ╚══════════════════════════════════════╝
            """
        }
        failure {
            echo "❌ Pipeline FAILED. Check logs above."
            sh """
                docker stop nginx-test-${BUILD_NUMBER} 2>/dev/null || true
                docker rm   nginx-test-${BUILD_NUMBER} 2>/dev/null || true
            """
        }
        always {
            echo "Build #${BUILD_NUMBER} finished."
        }
    }
}
```

---

## STEP 6: Create Jenkins Pipeline Job

1. Jenkins Dashboard → **New Item**
2. Name: `nginx-deploy-pipeline`
3. Type: **Pipeline** → Click OK
4. Under **General**:
   - ✅ Check **"GitHub project"**
   - Project URL: `https://github.com/YOUR_USER/nginx-jenkins-demo`
5. Under **Build Triggers**:
   - ✅ Check **"GitHub hook trigger for GITScm polling"**
6. Under **Pipeline**:
   - **Definition**: Pipeline script from SCM
   - **SCM**: Git
   - **Repository URL**: `https://github.com/YOUR_USER/nginx-jenkins-demo.git`
   - **Credentials**: select `github-credentials`
   - **Branch**: `*/main`
   - **Script Path**: `Jenkinsfile`
7. Click **Save**

---

## STEP 7: Test the Full Pipeline

### 7.1 Manual Trigger (first test)

Jenkins Dashboard → your pipeline → **Build Now**

Watch the stages execute in real time.

### 7.2 Automatic Trigger via GitHub Push

```bash
# Make a change to your repo
echo "<p>Updated!</p>" >> nginx/html/index.html
git add . && git commit -m "Update homepage"
git push origin main
```

Jenkins will automatically detect the push and run the pipeline!

### 7.3 Verify Nginx is Running

```bash
# Check container is up
docker ps | grep nginx-deployed

# Hit the site
curl http://localhost:8090

# Or open in browser
open http://localhost:8090
```

---

## STEP 8: Useful Commands

```bash
# View Jenkins logs
docker logs -f jenkins

# Restart Jenkins
docker restart jenkins

# Enter Jenkins container shell
docker exec -it jenkins bash

# View Nginx logs
docker logs -f nginx-deployed

# Stop everything
docker stop jenkins nginx-deployed
```

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `docker: command not found` inside Jenkins | Re-run: `docker exec -u root jenkins chmod 666 /var/run/docker.sock` |
| Webhook not triggering | Check ngrok URL, verify `/github-webhook/` path |
| Port 8090 already in use | Change `HOST_PORT` in Jenkinsfile |
| Permission denied on docker.sock | Run Jenkins container with `-u root` flag |
| Git credentials fail | Regenerate GitHub PAT, re-add to Jenkins credentials |

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────┐
│                    Docker Host                          │
│                                                         │
│   ┌─────────────┐    ┌──────────────────────────────┐  │
│   │   Jenkins   │    │        Pipeline Stages        │  │
│   │  Container  │───▶│  Checkout → Build → Test     │  │
│   │  :8080      │    │  → Deploy → Verify → Clean   │  │
│   └──────▲──────┘    └──────────────┬───────────────┘  │
│          │                          │                   │
│   GitHub │ Webhook                  ▼                   │
│   Push ──┘              ┌──────────────────────┐        │
│                         │   Nginx Container    │        │
│                         │   nginx-deployed     │        │
│                         │   :8090 → :80        │        │
│                         └──────────────────────┘        │
└─────────────────────────────────────────────────────────┘
                               ▲
                    http://localhost:8090
```
