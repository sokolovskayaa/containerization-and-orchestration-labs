FROM eclipse-temurin:25-jdk AS build

WORKDIR /workspace

COPY gradlew gradlew
COPY gradle gradle
COPY build.gradle settings.gradle ./
COPY src src

RUN chmod +x gradlew \
    && ./gradlew bootJar --no-daemon

FROM eclipse-temurin:25-jre

WORKDIR /app

COPY --from=build /workspace/build/libs/lab2-0.0.1-SNAPSHOT.jar app.jar

EXPOSE 8080

ENTRYPOINT ["java", "-jar", "/app/app.jar"]
