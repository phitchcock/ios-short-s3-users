import Kitura
import LoggerAPI
import HeliumLogger
import Foundation
import UsersService
import MySQL

// Disable stdout buffering (so log will appear)
setbuf(stdout, nil)

// Init logger
HeliumLogger.use(.info)

// Create connection string (use env variables, if exists)
let env = ProcessInfo.processInfo.environment
var connectionString = MySQLConnectionString(host: env["MYSQL_HOST"] ?? "127.0.0.1")
connectionString.port = Int(env["MYSQL_PORT"] ?? "3306") ?? 3306
connectionString.user = env["MYSQL_USER"] ?? "root"
connectionString.password = env["MYSQL_PASSWORD"] ?? "password"
connectionString.database = env["MYSQL_DATABASE"] ?? "game_night"

// Create connection pool
let pool = MySQLConnectionPool(connectionString: connectionString, poolSize: 10, defaultCharset: "utf8mb4")

// Create data accessor (uses pool to get connections and access data!)
let dataAccessor = UserMySQLDataAccessor(pool: pool)

// Check connection to database
if !dataAccessor.isConnected() {
    Log.error("Unable to connect to MySQL database: \(connectionString)")
}

// Create AccountKit client
let accountKitClient = AccountKitClient(
    session: URLSession(configuration: .default),
    appID: env["FACEBOOK_APP_ID"] ?? "FACEBOOK_APP_ID",
    appSecret: env["ACCOUNT_KIT_APP_SECRET"] ?? "ACCOUNT_KIT_APP_SECRET"
)

// FIXME: Use a service like S3 to deliver keys instead of injecting environment variables
// Remove extra backslash characters (extra backslashes are added to keys when injecting)
// Create JWT composer
let jwtComposer = JWTComposer(
    privateKey: env["PRIVATE_KEY"]?.replacingOccurrences(of: "\\n", with: "\n"),
    publicKey: env["PUBLIC_KEY"]?.replacingOccurrences(of: "\\n", with: "\n")
)

// Create handlers
let handlers = Handlers(dataAccessor: dataAccessor, accountKitClient: accountKitClient, jwtComposer: jwtComposer)

// Create router and middleware
let router = Router()
router.all("/*", middleware: BodyParser())
router.all("/*", middleware: AllRemoteOriginMiddleware())
router.all("/*", middleware: LoggerMiddleware())
router.options("/*", handler: handlers.getOptions)

// GET
router.get("/*", middleware: CheckRequestMiddleware(method: .get))
router.get("/*", middleware: JWTMiddleware(jwtComposer: jwtComposer, permissions: [.usersProfile, .usersAll]))
router.get("/users/search", handler: handlers.searchUsers)
router.get("/users/profile", handler: handlers.getCurrentUser)
router.get("/users/:id", handler: handlers.getUsers)
router.get("/users", handler: handlers.getUsers)

// POST
router.post("/*", middleware: CheckRequestMiddleware(method: .post))
router.post("/users/login", handler: handlers.login)
router.post("/users/logout", handler: handlers.logout)

// PUT
router.put("/*", middleware: CheckRequestMiddleware(method: .put))
router.put("/users/profile", middleware: JWTMiddleware(jwtComposer: jwtComposer, permissions: [.usersProfile, .usersAll]))
router.put("/users/profile", handler: handlers.updateProfile)
router.put("/users/favorites", middleware: JWTMiddleware(jwtComposer: jwtComposer, permissions: [.usersAll]))
router.put("/users/favorites", handler: handlers.updateFavorites)

// Add an HTTP server and connect it to the router
Kitura.addHTTPServer(onPort: 8080, with: router)

// Start the Kitura runloop (this call never returns)
Kitura.run()
