
pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
    }

    environment {
        IMAGE_REPO = 'suri175/kanban-dashboard'
        APP_CONTAINER = 'kanban-app'
        APP_PORT = '80'
        CONTAINER_PORT = '8080'
    }

    stages {

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
                        "${IMAGE_REPO}:${IMAGE_TAG}"
                }

                echo "Building image: ${FULL_IMAGE}"
            }
        }

        stage('Docker Build') {
            steps {
                sh '''
                    docker build \
                      -t "$FULL_IMAGE" \
                      .
                '''
            }
        }

        stage('Docker Registry Push') {
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
                        echo "$DOCKER_PASS" | \
                        docker login -u "$DOCKER_USER" \
                        --password-stdin

                        docker push "$FULL_IMAGE"

                        docker logout
                    '''
                }
            }
        }

        stage('Deploy to EC2') {
            steps {
                script {
                    withCredentials([
                        usernamePassword(
                            credentialsId: 'dockerhub-creds',
                            usernameVariable: 'DOCKER_USER',
                            passwordVariable: 'DOCKER_PASS'
                        )
                    ]) {
                        sh '''
                            set +x
                            echo "$DOCKER_PASS" | \
                            docker login -u "$DOCKER_USER" \
                            --password-stdin

                            docker pull "$FULL_IMAGE"
                            docker logout
                        '''
                    }

                    sh '''
                        set -eu

                        PREVIOUS_IMAGE=$(docker inspect \
                          --format='{{.Config.Image}}' \
                          "$APP_CONTAINER" 2>/dev/null || true)

                        echo "$PREVIOUS_IMAGE" > previous-image.txt

                        docker rm -f "$APP_CONTAINER" 2>/dev/null || true

                        docker run -d \
                          --name "$APP_CONTAINER" \
                          --restart unless-stopped \
                          --memory=512m \
                          --cpus=1 \
                          -p "$APP_PORT:$CONTAINER_PORT" \
                          "$FULL_IMAGE"
                    '''
                }
            }
        }

        stage('Health Check') {
            steps {
                sh '''
                    set -eu

                    HEALTHY=0

                    for i in $(seq 1 30); do
                        STATUS=$(docker inspect \
                          --format='{{.State.Health.Status}}' \
                          "$APP_CONTAINER" 2>/dev/null || true)

                        HTTP_CODE=$(curl -s -o /dev/null \
                          -w '%{http_code}' \
                          http://127.0.0.1/ || true)

                        if [ "$STATUS" = "healthy" ] && \
                           [ "$HTTP_CODE" = "200" ]; then
                            HEALTHY=1
                            break
                        fi

                        sleep 5
                    done

                    if [ "$HEALTHY" -ne 1 ]; then
                        echo "Deployment health check failed"
                        exit 1
                    fi

                    docker ps
                    echo "Application deployment successful"
                '''
            }
        }
    }

    post {
        success {
            echo "SUCCESS: ${FULL_IMAGE} deployed successfully."
        }

        failure {
            echo "Deployment failed. Starting rollback."

            sh '''
                set +e

                PREVIOUS_IMAGE=$(cat previous-image.txt 2>/dev/null || true)

                docker rm -f "$APP_CONTAINER" 2>/dev/null || true

                if [ -n "$PREVIOUS_IMAGE" ]; then
                    docker run -d \
                      --name "$APP_CONTAINER" \
                      --restart unless-stopped \
                      --memory=512m \
                      --cpus=1 \
                      -p "$APP_PORT:$CONTAINER_PORT" \
                      "$PREVIOUS_IMAGE"

                    echo "Previous application version restored"
                else
                    echo "No previous image available for rollback"
                fi
            '''
        }

        always {
            echo "Pipeline execution completed."
        }
    }
}
