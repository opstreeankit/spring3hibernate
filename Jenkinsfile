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

        // ─────────────────────────────────────────────────────────────────────
        // FIX: OWASP Dependency Check moved into its own stage, guarded by a
        // when-expression so it ONLY runs when:
        //   (a) the build was triggered by the weekly cron schedule, OR
        //   (b) someone manually sets RUN_OWASP=true on a parameterised build.
        //
        // ROOT CAUSE OF THE 30-MIN HANG:
        //   dependency-check-maven downloads the entire NVD database
        //   (~354,872 CVE records) on every build. Without an NVD API key,
        //   NIST throttles the feed to ~1 record/s → 60–90 minutes per run.
        //
        // HOW THE FIX WORKS:
        //   1. The plugin is removed from the default Maven lifecycle in
        //      pom.xml and placed inside the 'owasp' Maven profile.
        //   2. This Jenkins stage passes '-Powasp' to activate it only when
        //      the when-condition is true.
        //   3. The NVD API key is injected via Jenkins credentials
        //      (id: 'NVD_API_KEY') as a Secret Text credential.  The plugin
        //      uses the key to raise the NVD download rate from ~1 rec/s to
        //      ~50 rec/s — a 50× speedup on the first run (< 2 min after that
        //      because only deltas are downloaded from the local cache).
        //
        // HOW TO GET A FREE NVD API KEY:
        //   https://nvd.nist.gov/developers/request-an-api-key
        //   Then in Jenkins → Manage Jenkins → Credentials add a Secret Text
        //   credential with ID exactly 'NVD_API_KEY'.
        //
        // TO TRIGGER AN ON-DEMAND SCAN:
        //   Build with Parameter  RUN_OWASP = true
        //   (add a Boolean Parameter named RUN_OWASP to the job config).
        // ─────────────────────────────────────────────────────────────────────
        stage('OWASP Dependency Scan') {
            when {
                anyOf {
                    // Run automatically every Sunday at 02:00
                    triggeredBy 'TimerTrigger'
                    // Run when the job parameter RUN_OWASP is set to 'true'
                    expression { return params.RUN_OWASP == true }
                }
            }
            steps {
                // withCredentials injects the NVD API key without printing
                // it in the console log (masked automatically by Jenkins).
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
                    // Publish the HTML report to the Jenkins job page.
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

    // ─────────────────────────────────────────────────────────────────────
    // WEEKLY OWASP CRON SCHEDULE
    // Add this triggers block to your job's pipeline definition so the scan
    // runs automatically every Sunday at 02:00 without blocking normal CI.
    // If you use a Multibranch Pipeline or scan from SCM, put these triggers
    // inside a properties() step in the pipeline script instead.
    // ─────────────────────────────────────────────────────────────────────
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
