FROM openjdk:11
EXPOSE 8080
ARG JAR_FILE=react-and-spring-data-rest-*.jar
ADD ${JAR_FILE} app.jar
ENTRYPOINT ["java","-jar","/app.jar"]