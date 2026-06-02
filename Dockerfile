# ✅ FIX: Use Java 8 builder to match pom.xml <source>8</source><target>8</target>
FROM maven:3.9.9-eclipse-temurin-8 AS builder
RUN mvn -version
COPY . /usr/src/mymaven/
WORKDIR /usr/src/mymaven/
RUN mvn clean install
RUN mvn package

# ✅ FIX: Use Tomcat 7 with JRE 8 — JRE 7 cannot load Java 8 bytecode (class version 52.0)
FROM tomcat:7.0.109-jre8-alpine
MAINTAINER "opstree <opstree@gmail.com>"
RUN rm -rf /usr/local/tomcat/webapps/*
COPY --from=builder /usr/src/mymaven/target/Spring3HibernateApp.war /usr/local/tomcat/webapps/ROOT.war
WORKDIR /usr/local/tomcat/webapps/
EXPOSE 8080
