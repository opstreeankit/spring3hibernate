# ✅ Java 8 builder — matches pom.xml <source>8</source><target>8</target>
FROM maven:3.9.9-eclipse-temurin-8 AS builder

RUN mvn -version

COPY . /usr/src/mymaven/
WORKDIR /usr/src/mymaven/

RUN mvn clean install
RUN mvn package

# ✅ FIX: tomcat:7-jre8-alpine does NOT exist on Docker Hub.
#    Using tomcat:9.0-jre8 — the latest Tomcat version that supports JRE 8.
#    Tomcat 9 is fully backward compatible with Tomcat 7 servlet apps.
FROM tomcat:9.0-jre8

MAINTAINER "opstree <opstree@gmail.com>"

RUN rm -rf /usr/local/tomcat/webapps/*

COPY --from=builder /usr/src/mymaven/target/Spring3HibernateApp.war /usr/local/tomcat/webapps/ROOT.war

WORKDIR /usr/local/tomcat/webapps/

EXPOSE 8080
