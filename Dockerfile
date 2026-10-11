# --- Stage 1 : Build Maven ---
FROM eclipse-temurin:17-jdk-alpine AS build
WORKDIR /workspace

COPY mvnw .
COPY .mvn .mvn
COPY pom.xml .
COPY src src

RUN ./mvnw clean package -DskipTests

# --- Stage 2 : Runtime minimal ---
FROM eclipse-temurin:17-jre-alpine
WORKDIR /app

RUN addgroup -S arcway && adduser -S arcway -G arcway
USER arcway:arcway

COPY --from=build /workspace/target/*.jar app.jar

EXPOSE 8080 8081

ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75", "-XX:+ExitOnOutOfMemoryError", "-jar", "app.jar"]
