package com.darcode.arcway.testsupport;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.UUID;

import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.test.context.DynamicPropertyRegistrar;
import org.testcontainers.postgresql.PostgreSQLContainer;
import org.testcontainers.utility.MountableFile;

/**
 * Fournit UN PostgreSQL 17 réel, partagé par tous les tests d'intégration de la JVM.
 *
 * <p>Pourquoi un seul conteneur : le démarrer coûte plusieurs secondes. Il est
 * démarré une fois et détruit à la fin par Ryuk, le conteneur de nettoyage de
 * Testcontainers.
 *
 * <p>Pourquoi PAS {@code @ServiceConnection} : il brancherait l'application sur le
 * compte d'administration du conteneur, qui contourne la RLS. Ici l'application
 * se connecte avec {@code arcway_app} et Flyway avec {@code arcway_migrator},
 * exactement comme en production.
 */
@TestConfiguration(proxyBeanMethods = false)
public class PostgresContainerConfig {

    private static final String APP_ROLE = "arcway_app";
    private static final String MIGRATOR_ROLE = "arcway_migrator";

    // Mots de passe aléatoires, propres à cette exécution : rien à protéger, rien à versionner.
    private static final String APP_PASSWORD = randomSecret();
    private static final String MIGRATOR_PASSWORD = randomSecret();

    private static final PostgreSQLContainer POSTGRES = startContainer();

    /**
     * Injecte l'URL et les identifiants dans l'Environment Spring AVANT la création
     * du contexte. Ces valeurs l'emportent sur celles d'application-test.yaml.
     */
    @Bean
    public DynamicPropertyRegistrar databaseProperties() {
        return registry -> {
            String url = POSTGRES.getJdbcUrl();
            // Connexion de l'application : rôle sans privilège, soumis à la RLS
            registry.add("spring.datasource.url", () -> url);
            registry.add("spring.datasource.username", () -> APP_ROLE);
            registry.add("spring.datasource.password", () -> APP_PASSWORD);
            // Migrations Flyway : rôle propriétaire des objets
            registry.add("spring.flyway.url", () -> url);
            registry.add("spring.flyway.user", () -> MIGRATOR_ROLE);
            registry.add("spring.flyway.password", () -> MIGRATOR_PASSWORD);
        };
    }

    private static PostgreSQLContainer startContainer() {
        // Le script de création des rôles vit hors de src/ : on le lit depuis la
        // racine du projet (répertoire de travail de Failsafe).
        Path rolesScript = Path.of("ops", "db", "init", "01-roles.sql").toAbsolutePath();
        if (!Files.isRegularFile(rolesScript)) {
            throw new IllegalStateException("Script introuvable : " + rolesScript
                + " (les tests doivent être lancés depuis la racine du projet)");
        }

        PostgreSQLContainer container = new PostgreSQLContainer("postgres:17")
            .withDatabaseName("arcway_test")
            // 01-roles.sql lit ces deux variables avec \getenv
            .withEnv("ARCWAY_DB_MIGRATOR_PASSWORD", MIGRATOR_PASSWORD)
            .withEnv("ARCWAY_DB_APP_PASSWORD", APP_PASSWORD)
            // Le dossier docker-entrypoint-initdb.d est exécuté une fois, à l'initialisation
            .withCopyFileToContainer(MountableFile.forHostPath(rolesScript),
                "/docker-entrypoint-initdb.d/01-roles.sql");
        container.start();
        return container;
    }

    private static String randomSecret() {
        return UUID.randomUUID().toString().replace("-", "");
    }
}
