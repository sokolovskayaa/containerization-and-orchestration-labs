FROM eclipse-temurin:25-jdk AS build

WORKDIR /workspace

COPY gradlew gradlew
COPY gradle gradle
COPY build.gradle settings.gradle ./
COPY src src

RUN chmod +x gradlew \
    && ./gradlew installDist --no-daemon

FROM eclipse-temurin:25-jre

WORKDIR /app

RUN useradd --create-home --uid 10001 batch

COPY --from=build /workspace/build/install/batch/ ./

USER batch

ENTRYPOINT ["/app/bin/batch"]
