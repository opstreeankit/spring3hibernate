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
        steps {
            sh """
                docker build -t ${APP_NAME}:${IMAGE_TAG} .
            """

            sh """
                minikube image load ${APP_NAME}:${IMAGE_TAG}
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
