package main

import (
	"log"
	"os"

	"github.com/gin-gonic/gin"
	"github.com/joho/godotenv"
)

func main() {
	// Load .env file
	if err := godotenv.Load(); err != nil {
		log.Println("No .env file found")
	}

	// Set Gin mode
	gin.SetMode(gin.ReleaseMode)

	// Initialize router
	router := gin.Default()

	// CORS middleware
	router.Use(corsMiddleware())

	// Health check
	router.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{
			"status": "OK",
			"service": "seesea-api-go",
		})
	})

	// API routes
	v1 := router.Group("/api/v1")
	{
		// Vessels routes
		vessels := v1.Group("/vessels")
		{
			vessels.GET("/:chokepoint", getVessels)
			vessels.GET("/:chokepoint/summary", getVesselSummary)
		}

		// WebSocket
		router.GET("/ws", handleWebSocket)
	}

	// Start server
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	log.Printf("🚀 Go API server starting on port %s", port)
	if err := router.Run(":" + port); err != nil {
		log.Fatal(err)
	}
}

// CORS middleware
func corsMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Writer.Header().Set("Access-Control-Allow-Origin", "*")
		c.Writer.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		c.Writer.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")

		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(204)
			return
		}

		c.Next()
	}
}

// Placeholder handlers
func getVessels(c *gin.Context) {
	chokepoint := c.Param("chokepoint")
	c.JSON(200, gin.H{
		"chokepoint": chokepoint,
		"message":    "Vessel data will be implemented",
	})
}

func getVesselSummary(c *gin.Context) {
	chokepoint := c.Param("chokepoint")
	c.JSON(200, gin.H{
		"chokepoint": chokepoint,
		"message":    "Summary will be implemented",
	})
}

func handleWebSocket(c *gin.Context) {
	c.JSON(200, gin.H{
		"message": "WebSocket will be implemented",
	})
}
