
pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
        timeout(time: 30, unit: 'MINUTES')
    }

    environment {
        IMAGE_REPO = 'suri175/kanban-dashboard'
        APP_CONTAINER = 'kanban-app'
        APP_PORT = '80'
        CONTAINER_PORT = '8080'
    }
    triggers {
        githubPush()
    }

    stages {

        // 1. Checkout source code from GitHub
        stage('Checkout') {
            steps {
                checkout scm

                script {
                    env.GIT_SHA = sh(
                        script: 'git rev-parse --short=12 HEAD',
                        returnStdout: true
                    ).trim()

                    env.IMAGE_TAG =
                        "${BUILD_NUMBER}-${env.GIT_SHA}"

                    env.FULL_IMAGE =
                        "${IMAGE_REPO}:${env.IMAGE_TAG}"

                    env.PREVIOUS_IMAGE = ''
                }

                echo "Building image: ${FULL_IMAGE}"
            }
        }

        // 2. Docker Hub authentication BEFORE build
        stage('Docker Hub Login') {
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'dockerhub-creds',
                        usernameVariable: 'DOCKER_USER',
                        passwordVariable: 'DOCKER_PASS'
                    )
                ]) {
                    sh '''
                        set +x

                        echo "$DOCKER_PASS" | docker login \
                          -u "$DOCKER_USER" \
                          --password-stdin
                    '''
                }
            }
        }

        // 3. Pull base images and build application
        stage('Docker Build') {
            steps {
                sh '''
                    set -eu

                    echo "Pulling Node.js base image..."
                    docker pull node:22-alpine

                    echo "Pulling Nginx base image..."
                    docker pull nginx:alpine

                    echo "Building Docker image..."

                    docker build \
                      --progress=plain \
                      --pull \
                      -t "$FULL_IMAGE" \
                      .

                    echo "Docker build completed"

                    docker images
                '''
            }
        }

        // 4. Push image to Docker Hub
        stage('Docker Registry Push') {
            steps {
                sh '''
                    set -eu

                    echo "Pushing image: $FULL_IMAGE"

                    docker push "$FULL_IMAGE"

                    echo "Image pushed successfully"
                '''
            }
        }

        // 5. Capture previous version and deploy
        stage('Deploy to EC2') {
            steps {
                script {

                    // Capture existing application image
                    env.PREVIOUS_IMAGE = sh(
                        script: '''
                            docker inspect \
                              --format='{{.Config.Image}}' \
                              "$APP_CONTAINER" 2>/dev/null || true
                        ''',
                        returnStdout: true
                    ).trim()

                    echo "Previous image: ${env.PREVIOUS_IMAGE}"

                    // Pull new image
                    sh '''
                        set -eu

                        echo "Pulling new image..."
                        docker pull "$FULL_IMAGE"
                    '''

                    // Deploy new container
                    sh '''
                        set -eu

                        echo "Stopping previous container..."

                        docker rm -f "$APP_CONTAINER" 2>/dev/null || true

                        echo "Starting new application container..."

                        docker run -d \
                          --name "$APP_CONTAINER" \
                          --restart unless-stopped \
                          --memory=512m \
                          --cpus=1 \
                          -p "$APP_PORT:$CONTAINER_PORT" \
                          "$FULL_IMAGE"

                        echo "Container deployment completed"
                    '''
                }
            }
        }

        // 6. Application health validation
        stage('Health Check') {
            steps {
                sh '''
                    set -eu

                    HEALTHY=0

                    echo "Checking application health..."

                    for i in $(seq 1 30); do

                        STATUS=$(docker inspect \
                          --format='{{.State.Health.Status}}' \
                          "$APP_CONTAINER" 2>/dev/null || true)

                        HTTP_CODE=$(curl -s -o /dev/null \
                          --max-time 3 \
                          -w '%{http_code}' \
                          http://127.0.0.1/ || true)

                        echo "Attempt $i: Health=$STATUS HTTP=$HTTP_CODE"

                        if [ "$STATUS" = "healthy" ] && \
                           [ "$HTTP_CODE" = "200" ]; then

                            HEALTHY=1
                            break
                        fi

                        sleep 5
                    done

                    if [ "$HEALTHY" -ne 1 ]; then
                        echo "Application health check failed"
                        docker logs "$APP_CONTAINER" || true
                        exit 1
                    fi

                    echo "Application is healthy"

                    docker ps

                    echo "Deployment successful"
                '''
            }
        }
    }

    post {

        success {
            echo """
            ========================================
            SUCCESS: Application deployed
            Image: ${env.FULL_IMAGE}
            Container: ${env.APP_CONTAINER}
            URL: http://EC2-PUBLIC-IP
            ========================================
            """
        }

        failure {
            echo "Deployment failed. Starting rollback..."

            script {
                if (env.PREVIOUS_IMAGE?.trim()) {

                    sh '''
                        set +e

                        echo "Restoring previous image..."

                        docker rm -f "$APP_CONTAINER" 2>/dev/null || true

                        docker run -d \
                          --name "$APP_CONTAINER" \
                          --restart unless-stopped \
                          --memory=512m \
                          --cpus=1 \
                          -p "$APP_PORT:$CONTAINER_PORT" \
                          "$PREVIOUS_IMAGE"

                        echo "Rollback command executed"
                    '''

                } else {

                    echo "No previous image available for rollback."
                }
            }
        }

        always {
            sh '''
                docker logout || true
            '''

            echo "Pipeline execution completed."
        }
    }
}
