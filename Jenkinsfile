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

        // FIX: Create namespaces before any deployment stage.
        // Previously the pipeline ran 'kubectl apply -n dev ...' without
        // ensuring the 'dev' namespace existed, causing:
        //   Error from server (NotFound): namespaces "dev" not found
        // The '||' pattern is idempotent — namespaces are only created if
        // they don't already exist, so re-runs are safe.
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

        // FIX 2: Dedicated test stage so JaCoCo actually instruments code.
        // Previously 'mvn clean package -DskipTests' skipped all tests,
        // resulting in 0% coverage. 'mvn verify -DskipITs' runs unit tests
        // only (skips integration tests) and triggers the full JaCoCo lifecycle
        // (prepare-agent → surefire → merge → report → check).
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

        stage('Build Docker Image') {
            // ROOT CAUSE: Running 'minikube start' inside the Jenkins pipeline
            // as root with --driver=docker causes K8S_APISERVER_MISSING because
            // the kube-apiserver process never starts due to cgroup v2 conflicts
            // between the outer Docker daemon (Jenkins) and the inner minikube
            // Docker-in-Docker container on Ubuntu 22.04.
            //
            // FIX: Never start minikube in the pipeline. Instead:
            //   1. Minikube is started ONCE manually on the host and left running
            //      as a persistent cluster (see prerequisite note below).
            //   2. The pipeline uses 'eval $(minikube docker-env)' to redirect
            //      DOCKER_HOST to minikube's internal Docker socket.
            //   3. 'docker build' then writes the image directly into minikube's
            //      daemon — no 'minikube image load' step needed at all.
            //
            // PREREQUISITE (one-time setup on the host, not in this pipeline):
            //   Run this once as the same user Jenkins runs as:
            //     $ minikube start --driver=docker --kubernetes-version=v1.35.1
            //   Leave minikube running. Jenkins will connect to it every build
            //   without ever starting or stopping it.
            //
            // WHY THIS SOLVES THE CGROUP PROBLEM:
            //   minikube start (the expensive part that spawns kube-apiserver)
            //   never runs inside the pipeline. Jenkins only talks to an already-
            //   healthy cluster via its Docker socket. No cgroup negotiation,
            //   no API server bootstrap, no 6-minute timeout.
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

                // Build the Docker image directly into minikube's internal daemon.
                // eval $(minikube docker-env) exports four env vars for this shell:
                //   DOCKER_TLS_VERIFY, DOCKER_HOST, DOCKER_CERT_PATH,
                //   MINIKUBE_ACTIVE_DOCKERD
                // These redirect all docker commands to minikube's socket.
                // The host Docker daemon is completely unaffected.
                // Because the image lands inside minikube's daemon, Kubernetes can
                // pull it with imagePullPolicy: Never — no registry required.
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
                    sed -i 's|IMAGE_PLACEHOLDER|${APP_NAME}:${IMAGE_TAG}|g' k8s/dev/deployment.yaml
                    kubectl apply -n dev -f k8s/dev/deployment.yaml
                    kubectl apply -n dev -f k8s/dev/service.yaml
                    kubectl rollout status deployment/spring-app \
                    -n dev --timeout=180s
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
                    sed -i 's|IMAGE_PLACEHOLDER|${APP_NAME}:${IMAGE_TAG}|g' k8s/staging/deployment.yaml
                    kubectl apply -n staging -f k8s/staging/deployment.yaml
                    kubectl apply -n staging -f k8s/staging/service.yaml
                    kubectl rollout status deployment/spring-app \
                    -n staging --timeout=180s
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
                    sed -i 's|IMAGE_PLACEHOLDER|${APP_NAME}:${IMAGE_TAG}|g' k8s/prod/green-deployment.yaml
                    kubectl apply -n prod -f k8s/prod/green-deployment.yaml
                    kubectl rollout status deployment/spring-app-green \
                    -n prod --timeout=180s
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
    post {
        success {
            echo 'Deployment completed successfully.'
        }
        failure {
            echo 'Deployment failed. Rolling back...'
            // FIX 3: Guard rollback with an existence check before attempting
            // 'kubectl rollout undo'. Previously the pipeline tried to roll back
            // spring-app-green even when it had never been deployed (i.e. the
            // pipeline failed before the 'Deploy GREEN' stage), causing a
            // misleading "NotFound" error in the post-failure logs.
            sh '''
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
