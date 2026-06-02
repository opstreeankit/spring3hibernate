# ✅ FIX: Java 8 builder to match pom.xml <source>8</source><target>8</target>
# Previous: eclipse-temurin-11 (Java 11 builder with Java 8 bytecode target = mismatch)
FROM maven:3.9.9-eclipse-temurin-8 AS builder

RUN mvn -version

COPY . /usr/src/mymaven/
WORKDIR /usr/src/mymaven/

RUN mvn clean install
RUN mvn package

# ✅ FIX: Tomcat 7 with JRE 8 instead of JRE 7
# Previous: tomcat:7-jre7-alpine (Java 7 runtime cannot load Java 8 class files = UnsupportedClassVersionError)
FROM tomcat:7.0.109-jre8-alpine

MAINTAINER "opstree <opstree@gmail.com>"

RUN rm -rf /usr/local/tomcat/webapps/*

COPY --from=builder /usr/src/mymaven/target/Spring3HibernateApp.war /usr/local/tomcat/webapps/ROOT.war

WORKDIR /usr/local/tomcat/webapps/

EXPOSE 8080
