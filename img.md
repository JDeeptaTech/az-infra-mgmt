``` groovy
// ============================================================================
// REUSABLE HTTP HELPER LIBRARY
// ============================================================================

/**
 * Sends a GET request
 * @param url: The target URL
 * @param credId: Jenkins Credential ID for authentication
 * @return: The JSON content response as a Map/List (parsed)
 */
def httpGet(String url, String credId) {
    echo " -> GET: ${url}"
    def response = httpRequest(
        authentication: credId,
        httpMode: 'GET',
        url: url,
        contentType: 'APPLICATION_JSON',
        acceptType: 'APPLICATION_JSON',
        ignoreSslErrors: true,
        consoleLogResponseBody: true,
        validResponseCodes: '100:399'
    )
    return parseResponse(response)
}

/**
 * Sends a POST request with a payload
 */
def httpPost(String url, String credId, String requestBody) {
    echo " -> POST: ${url}"
    def response = httpRequest(
        authentication: credId,
        httpMode: 'POST',
        url: url,
        requestBody: requestBody,
        contentType: 'APPLICATION_JSON',
        acceptType: 'APPLICATION_JSON',
        ignoreSslErrors: true,
        consoleLogResponseBody: true,
        validResponseCodes: '100:399'
    )
    return parseResponse(response)
}

/**
 * Sends a PATCH request (Useful for updating GitHub Releases)
 */
def httpPatch(String url, String credId, String requestBody) {
    echo " -> PATCH: ${url}"
    def response = httpRequest(
        authentication: credId,
        httpMode: 'PATCH',
        url: url,
        requestBody: requestBody,
        contentType: 'APPLICATION_JSON',
        acceptType: 'APPLICATION_JSON',
        ignoreSslErrors: true,
        consoleLogResponseBody: true,
        validResponseCodes: '100:399'
    )
    return parseResponse(response)
}

/**
 * Helper to parse JSON strings into Groovy objects safely
 */
@NonCPS
def parseResponse(response) {
    if (response.content) {
        def jsonSlurper = new groovy.json.JsonSlurperClassic()
        return jsonSlurper.parseText(response.content)
    }
    return [:] // Return empty map if no content
}

pipeline {
    agent any
    
    // Define your global variables
    environment {
        GIT_CRED_ID = ''
        REPO_API = " d"
    }

    stages {
        stage('Release Management') {
            steps {
                script {
                    // --- 1. GET EXAMPLE ---
                    echo "Checking latest release..."
                    try {
                        def latestRelease = httpGet("${REPO_API}/releases/latest", GIT_CRED_ID)
                        echo "Latest version is: ${latestRelease.tag_name}"
                    } catch (Exception e) {
                        echo "No latest release found (First run?)"
                    }

                    // --- 2. POST EXAMPLE (Create Tag/Release) ---
                    echo "Creating new release..."
                    
                    def releasePayload = """{
                        "tag_name": "${env.NEW_VERSION}",
                        "target_commitish": "${sha}",
                        "name": "${env.NEW_VERSION}",
                        "body": "Automated release",
                        "draft": false,
                        "prerelease": true
                    }"""
                    
                    // Call the library function
                    def releaseResp = httpPost("${REPO_API}/releases", GIT_CRED_ID, releasePayload)
                    
                    // Access JSON properties directly!
                    def releaseId = releaseResp.id
                    echo "Created Release ID: ${releaseId}"

                    // --- 3. PATCH EXAMPLE (Update Release) ---
                    echo "Updating release to mark as stable..."
                    def patchPayload = '{"prerelease": false}'
                    
                    httpPatch("${REPO_API}/releases/${releaseId}", GIT_CRED_ID, patchPayload)
                }
            }
        }
    }
}
```
