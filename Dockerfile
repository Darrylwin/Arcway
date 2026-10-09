# syntax=docker/dockerfile:1

# ======================================================
# Étape 1 : build
# ======================================================
FROM eclipse-temurin:17-jdk AS build
WORKDIR /workspace

# 1. Dépendances
COPY --chmod=0755 mvnw ./
COPY .mvn .mvn
COPY pom.xml ./
RUN --mount=type=cache,target=/root/.m2 \
    ./mvnw -B -q dependency:go-offline

# 2. Le code
COPY src src
RUN --mount=type=cache,target=/root/.m2 \
    ./mvnw -B -DskipTests package \
    && cp target/*.jar application.jar

# 3. Découpe du jar en couches.
RUN java -Djarmode=tools -jar application.jar extract --layers --destination extracted

# ==========================================================
# Étape 2 : exécution
# ==========================================================
FROM eclipse-temurin:17-jre AS runtime

RUN groupadd --system --gid 10001 arcway \
    && useradd --system --uid 10001 --gid arcway \
       --no-create-home --shell /usr/sbin/nologin arcway

WORKDIR /app

# Ordre du moins changeant au plus changeant : maximise le cache.
COPY --from=build --chown=arcway:arcway /workspace/extracted/dependencies/ ./
COPY --from=build --chown=arcway:arcway /workspace/extracted/spring-boot-loader/ ./
COPY --from=build --chown=arcway:arcway /workspace/extracted/snapshot-dependencies/ ./
COPY --from=build --chown=arcway:arcway /workspace/extracted/application/ ./

USER arcway

EXPOSE 8080

ENTRYPOINT ["java", \
    "-XX:MaxRAMPercentage=75", \
    "-XX:+ExitOnOutOfMemoryError", \
    "-jar", "application.jar"]
