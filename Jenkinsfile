pipeline {
    agent any
    environment {
        APP_NAME = "spring3hibernate"
        IMAGE_TAG = "${BUILD_NUMBER}"
    }
    options {
        timestamps()
        disableConcurrentBuilds()
    }
    stages {
        stage('Debug Maven') {
            steps {
                sh '''
                    echo "===== JAVA VERSION ====="
                    java -version
                    echo "===== MAVEN VERSION ====="
                    mvn -version
                    echo "===== DOCKER VERSION ====="
                    docker --version
                '''
            }
        }

        stage('Setup Namespaces') {
            steps {
                sh '''
                    echo "===== ENSURING KUBERNETES NAMESPACES EXIST ====="
                    kubectl get namespace dev      || kubectl create namespace dev
                    kubectl get namespace staging  || kubectl create namespace staging
                    kubectl get namespace prod     || kubectl create namespace prod
                    echo "===== NAMESPACES READY ====="
                    kubectl get namespaces
                '''
            }
        }

        stage('Build Application') {
            steps {
                sh '''
                    mvn clean package -DskipTests
                '''
            }
        }

        stage('Test & Coverage') {
            steps {
                sh '''
                    mvn verify -DskipITs
                '''
            }
            post {
                always {
                    junit '**/target/surefire-reports/*.xml'
                    jacoco(
                        execPattern:         '**/target/jacoco-merged.exec',
                        classPattern:        '**/target/classes',
                        sourcePattern:       '**/src/main/java',
                        changeBuildStatus:   true,
                        minimumLineCoverage:    '80',
                        minimumBranchCoverage:  '75',
                        minimumClassCoverage:   '80'
                    )
                }
            }
        }

        stage('OWASP Dependency Scan') {
            when {
                anyOf {
                    triggeredBy 'TimerTrigger'
                    expression { return params.RUN_OWASP == true }
                }
            }
            steps {
                withCredentials([string(credentialsId: 'NVD_API_KEY', variable: 'NVD_KEY')]) {
                    sh """
                        echo "===== OWASP DEPENDENCY CHECK ====="
                        mvn verify -Powasp -DnvdApiKey=${NVD_KEY} -DskipTests
                        echo "===== OWASP SCAN COMPLETE ====="
                    """
                }
            }
            post {
                always {
                    publishHTML(target: [
                        allowMissing:          true,
                        alwaysLinkToLastBuild: true,
                        keepAll:               true,
                        reportDir:             'target',
                        reportFiles:           'dependency-check-report.html',
                        reportName:            'OWASP Dependency Check'
                    ])
                }
            }
        }

        stage('Build Docker Image') {
            steps {
                sh '''
                    echo "===== VERIFYING MINIKUBE IS REACHABLE ====="
                    MINIKUBE_HOST=$(minikube status --format='{{.Host}}' 2>/dev/null || echo "Nonexistent")
                    if ! echo "$MINIKUBE_HOST" | grep -q "Running"; then
                        echo "------------------------------------------------------------"
                        echo "ERROR: Minikube is not running (status: $MINIKUBE_HOST)"
                        echo ""
                        echo "Please run this ONCE on the host machine as the Jenkins user:"
                        echo "  minikube start --driver=docker --kubernetes-version=v1.35.1"
                        echo ""
                        echo "Leave minikube running between builds — the pipeline will"
                        echo "connect to it without ever starting or stopping it."
                        echo "------------------------------------------------------------"
                        exit 1
                    fi
                    echo "Minikube is Running. Cluster is healthy."
                    minikube status
                '''

                sh """
                    eval \$(minikube docker-env)
                    echo "===== BUILDING INTO MINIKUBE DOCKER DAEMON ====="
                    docker build -t ${APP_NAME}:${IMAGE_TAG} .
                    echo "===== VERIFYING IMAGE IS VISIBLE TO MINIKUBE ====="
                    docker images | grep ${APP_NAME}
                """
            }
        }

        stage('Deploy DEV') {
            steps {
                milestone(1)
                sh """
                    eval \$(minikube docker-env)

                    # Replace placeholder with real image tag
                    sed -i 's|IMAGE_PLACEHOLDER|${APP_NAME}:${IMAGE_TAG}|g' k8s/dev/deployment.yaml

                    kubectl apply -n dev -f k8s/dev/deployment.yaml
                    kubectl apply -n dev -f k8s/dev/service.yaml

                    # FIX: Restore placeholder immediately after apply so the
                    # next build always has IMAGE_PLACEHOLDER to substitute.
                    # Without this, sed becomes a no-op on the second run and
                    # Kubernetes sees an unchanged spec — leaving the old broken
                    # pod in place instead of rolling out the new image.
                    sed -i 's|${APP_NAME}:${IMAGE_TAG}|IMAGE_PLACEHOLDER|g' k8s/dev/deployment.yaml

                    kubectl rollout status deployment/spring-app -n dev --timeout=180s
                """
            }
        }

        stage('DEV Health Check') {
            steps {
                script {
                    retry(5) {
                        sleep 15
                        httpRequest(
                            url: 'http://localhost:30080/',
                            validResponseCodes: '200'
                        )
                    }
                }
            }
        }

        stage('Approve STAGING') {
            steps {
                input(
                    message: 'Deploy to STAGING?',
                    ok: 'Deploy'
                )
            }
        }

        stage('Deploy STAGING') {
            steps {
                milestone(2)
                sh """
                    eval \$(minikube docker-env)

                    # Replace placeholder with real image tag
                    sed -i 's|IMAGE_PLACEHOLDER|${APP_NAME}:${IMAGE_TAG}|g' k8s/staging/deployment.yaml

                    kubectl apply -n staging -f k8s/staging/deployment.yaml
                    kubectl apply -n staging -f k8s/staging/service.yaml

                    # FIX: Restore placeholder immediately after apply
                    sed -i 's|${APP_NAME}:${IMAGE_TAG}|IMAGE_PLACEHOLDER|g' k8s/staging/deployment.yaml

                    kubectl rollout status deployment/spring-app -n staging --timeout=180s
                """
            }
        }

        stage('STAGING Health Check') {
            steps {
                script {
                    retry(5) {
                        sleep 15
                        httpRequest(
                            url: 'http://localhost:30081/',
                            validResponseCodes: '200'
                        )
                    }
                }
            }
        }

        stage('Approve PRODUCTION') {
            steps {
                input(
                    message: 'Deploy to Production?',
                    ok: 'Deploy'
                )
            }
        }

        stage('Deploy GREEN') {
            steps {
                milestone(3)
                sh """
                    eval \$(minikube docker-env)

                    # Replace placeholder with real image tag
                    sed -i 's|IMAGE_PLACEHOLDER|${APP_NAME}:${IMAGE_TAG}|g' k8s/prod/green-deployment.yaml

                    kubectl apply -n prod -f k8s/prod/green-deployment.yaml

                    # FIX: Restore placeholder immediately after apply
                    sed -i 's|${APP_NAME}:${IMAGE_TAG}|IMAGE_PLACEHOLDER|g' k8s/prod/green-deployment.yaml

                    kubectl rollout status deployment/spring-app-green -n prod --timeout=180s
                """
            }
        }

        stage('GREEN Health Check') {
            steps {
                script {
                    retry(10) {
                        sleep 10
                        httpRequest(
                            url: 'http://localhost:30082/',
                            validResponseCodes: '200'
                        )
                    }
                }
            }
        }

        stage('Switch Traffic To GREEN') {
            steps {
                sh '''
                    kubectl patch service spring-app-service \
                    -n prod \
                    -p '{"spec":{"selector":{"app":"spring-app","color":"green"}}}'
                '''
            }
        }

        stage('Production Verification') {
            steps {
                script {
                    retry(5) {
                        sleep 10
                        httpRequest(
                            url: 'http://localhost:30082/',
                            validResponseCodes: '200'
                        )
                    }
                }
            }
        }

        stage('Scale Down BLUE') {
            steps {
                sh '''
                    kubectl scale deployment spring-app-blue \
                    --replicas=0 \
                    -n prod
                '''
            }
        }
    }

    // triggers {
    //     cron('0 2 * * 0')   // every Sunday at 02:00
    // }

    post {
        success {
            echo 'Deployment completed successfully.'
        }
        failure {
            echo 'Deployment failed. Rolling back...'
            sh '''
                # Restore any deployment.yaml files that may have had their
                # placeholder replaced before the failure, so the next build
                # is not stuck with a hardcoded image tag in the YAML.
                for f in k8s/dev/deployment.yaml k8s/staging/deployment.yaml k8s/prod/green-deployment.yaml; do
                    if [ -f "$f" ]; then
                        sed -i "s|${APP_NAME}:[0-9]*|IMAGE_PLACEHOLDER|g" "$f" 2>/dev/null || true
                    fi
                done

                if kubectl get deployment spring-app-green -n prod > /dev/null 2>&1; then
                    echo "Green deployment found — switching traffic back to blue and rolling back..."
                    kubectl patch service spring-app-service \
                        -n prod \
                        -p '{"spec":{"selector":{"app":"spring-app","color":"blue"}}}'
                    kubectl rollout undo deployment/spring-app-green -n prod
                else
                    echo "Green deployment not found — pipeline failed before prod stage, no rollback needed."
                fi
            '''
        }
        always {
            cleanWs()
        }
    }
}
