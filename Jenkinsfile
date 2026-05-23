pipeline {
    agent any

    environment {
        IMAGE_NAME     = "nginx-app"
        CONTAINER_NAME = "nginx-deployed"
        HOST_PORT      = "8090"
        CONTAINER_PORT = "80"
    }

    triggers {
        githubPush()
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
                    # Get docker host IP
            HOST_IP=\$(ip route | grep default | awk '{print \$3}')
            
            docker run --rm -d \
              --name nginx-test-${BUILD_NUMBER} \
              -p 8099:80 \
              ${IMAGE_NAME}:${BUILD_NUMBER}
            
            sleep 5
            curl -f http://\${HOST_IP}:8099 || exit 1
            docker stop nginx-test-${BUILD_NUMBER}
            echo "✅ Test passed!"
                """
            }
        }

        stage('Deploy Nginx Container') {
            steps {
                echo "🚀 Deploying Nginx container..."
                sh """
                    docker stop ${CONTAINER_NAME} 2>/dev/null || true
                    docker rm   ${CONTAINER_NAME} 2>/dev/null || true

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
            echo "✅ PIPELINE SUCCEEDED! Nginx running on port ${HOST_PORT}"
        }
        failure {
            echo "❌ Pipeline FAILED."
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
