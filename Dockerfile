#FROM maven:3.3-jdk-8 as builder
FROM maven:3.9.9-eclipse-temurin-11 AS builder

RUN mvn -version
COPY . /usr/src/mymaven/
WORKDIR /usr/src/mymaven/
RUN mvn clean install
RUN mvn package 

FROM tomcat:7-jre7-alpine
MAINTAINER "opstree <opstree@gmail.com>"
RUN rm -rf /usr/local/tomcat/webapps/*
COPY --from=builder /usr/src/mymaven/target/Spring3HibernateApp.war /usr/local/tomcat/webapps/ROOT.war
WORKDIR /usr/local/tomcat/webapps/
EXPOSE 8080
