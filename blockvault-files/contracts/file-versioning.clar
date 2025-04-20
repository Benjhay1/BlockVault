;; Error Codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-FILE-NOT-FOUND (err u101))
(define-constant ERR-INVALID-VERSION (err u102))
(define-constant ERR-VERSION-EXISTS (err u103))
(define-constant ERR-NOT-FILE-OWNER (err u104))
(define-constant ERR-UNAUTHORIZED-EDITOR (err u105))
(define-constant ERR-NOT-INITIALIZED (err u106))
(define-constant ERR-ALREADY-INITIALIZED (err u107))
(define-constant ERR-EMPTY-STRING (err u108))

;; Data Structures

;; File version structure
(define-map file-versions 
  { file-id: (string-ascii 64), version: uint }
  { 
    hash: (string-ascii 64),
    timestamp: uint,
    metadata: (string-utf8 256),
    uploader: principal
  }
)

;; File metadata structure
(define-map files 
  { file-id: (string-ascii 64) }
  {
    owner: principal,
    name: (string-utf8 128),
    description: (string-utf8 256),
    current-version: uint,
    created-at: uint,
    last-modified: uint,
    is-private: bool
  }
)

;; Track file access permissions
(define-map file-editors
  { file-id: (string-ascii 64), editor: principal }
  { can-edit: bool, can-view: bool }
)

;; Admin controls
(define-data-var contract-owner principal tx-sender)
(define-data-var contract-initialized bool false)

;; Input validation helpers
(define-private (is-valid-string-ascii (value (string-ascii 64)))
  (> (len value) u0))

(define-private (is-valid-string-utf8-256 (value (string-utf8 256)))
  (not (is-eq value u"")))

(define-private (is-valid-string-utf8-128 (value (string-utf8 128)))
  (not (is-eq value u"")))

;; Public Functions

;; Initialize the contract - can only be called once
(define-public (initialize)
  (begin
    (asserts! (not (var-get contract-initialized)) ERR-ALREADY-INITIALIZED)
    (var-set contract-initialized true)
    (ok true)
  )
)

;; Create a new file
(define-public (create-file (file-id (string-ascii 64)) 
                           (name (string-utf8 128)) 
                           (description (string-utf8 256))
                           (hash (string-ascii 64))
                           (metadata (string-utf8 256))
                           (is-private bool))
  (begin
    ;; Validate inputs
    (asserts! (is-valid-string-ascii file-id) ERR-EMPTY-STRING)
    (asserts! (is-valid-string-utf8-128 name) ERR-EMPTY-STRING)
    (asserts! (is-valid-string-utf8-256 description) ERR-EMPTY-STRING)
    (asserts! (is-valid-string-ascii hash) ERR-EMPTY-STRING)
    (asserts! (is-valid-string-utf8-256 metadata) ERR-EMPTY-STRING)
    
    ;; Check contract is initialized
    (asserts! (var-get contract-initialized) ERR-NOT-INITIALIZED)
    
    ;; Check file doesn't already exist
    (asserts! (is-none (map-get? files {file-id: file-id})) ERR-FILE-NOT-FOUND)

    ;; Store file metadata
    (map-set files 
      {file-id: file-id}
      {
        owner: tx-sender,
        name: name,
        description: description,
        current-version: u1,
        created-at: (unwrap-panic (get-block-info? time u0)),
        last-modified: (unwrap-panic (get-block-info? time u0)),
        is-private: is-private
      }
    )

    ;; Store initial version
    (map-set file-versions
      {file-id: file-id, version: u1}
      {
        hash: hash,
        timestamp: (unwrap-panic (get-block-info? time u0)),
        metadata: metadata,
        uploader: tx-sender
      }
    )

    ;; Add owner as editor automatically
    (map-set file-editors
      {file-id: file-id, editor: tx-sender}
      {can-edit: true, can-view: true}
    )

    (ok u1) ;; Return the version number
  )
)

;; Upload a new version of a file
(define-public (upload-version (file-id (string-ascii 64)) 
                              (hash (string-ascii 64))
                              (metadata (string-utf8 256)))
  (begin
    ;; Validate inputs
    (asserts! (is-valid-string-ascii file-id) ERR-EMPTY-STRING)
    (asserts! (is-valid-string-ascii hash) ERR-EMPTY-STRING)
    (asserts! (is-valid-string-utf8-256 metadata) ERR-EMPTY-STRING)
    
    ;; Check contract is initialized
    (asserts! (var-get contract-initialized) ERR-NOT-INITIALIZED)
    
    (let 
      (
        (file-data (unwrap! (map-get? files {file-id: file-id}) ERR-FILE-NOT-FOUND))
        (next-version (+ (get current-version file-data) u1))
        (permissions (default-to {can-edit: false, can-view: false} 
                      (map-get? file-editors {file-id: file-id, editor: tx-sender})))
      )
      ;; Check that user is owner or has edit permissions
      (asserts! (or 
                 (is-eq tx-sender (get owner file-data))
                 (get can-edit permissions)) 
                ERR-UNAUTHORIZED-EDITOR)
      
      ;; Store new version
      (map-set file-versions
        {file-id: file-id, version: next-version}
        {
          hash: hash,
          timestamp: (unwrap-panic (get-block-info? time u0)),
          metadata: metadata,
          uploader: tx-sender
        }
      )
      
      ;; Update file metadata
      (map-set files
        {file-id: file-id}
        (merge file-data {
          current-version: next-version,
          last-modified: (unwrap-panic (get-block-info? time u0))
        })
      )
      
      (ok next-version)
    )
  )
)

;; Get file information
(define-read-only (get-file-info (file-id (string-ascii 64)))
  (begin
    ;; Validate file-id
    (asserts! (is-valid-string-ascii file-id) ERR-EMPTY-STRING)
    
    (let 
      (
        (file-data (unwrap! (map-get? files {file-id: file-id}) ERR-FILE-NOT-FOUND))
        (permissions (default-to {can-edit: false, can-view: false} 
                      (map-get? file-editors {file-id: file-id, editor: tx-sender})))
      )
      ;; For private files, only allow access to owner or users with permission
      (asserts! (or 
                 (not (get is-private file-data))
                 (is-eq tx-sender (get owner file-data))
                 (get can-view permissions))
                ERR-NOT-AUTHORIZED)
      
      (ok file-data)
    )
  )
)

;; Get specific version information
(define-read-only (get-version (file-id (string-ascii 64)) (version uint))
  (begin
    ;; Validate file-id
    (asserts! (is-valid-string-ascii file-id) ERR-EMPTY-STRING)
    
    (let 
      (
        (file-data (unwrap! (map-get? files {file-id: file-id}) ERR-FILE-NOT-FOUND))
        (permissions (default-to {can-edit: false, can-view: false} 
                      (map-get? file-editors {file-id: file-id, editor: tx-sender})))
        (current-version (get current-version file-data))
      )
      ;; Check version is valid
      (asserts! (<= version current-version) ERR-INVALID-VERSION)
      
      ;; For private files, only allow access to owner or users with permission
      (asserts! (or 
                 (not (get is-private file-data))
                 (is-eq tx-sender (get owner file-data))
                 (get can-view permissions))
                ERR-NOT-AUTHORIZED)
      
      (ok (unwrap! (map-get? file-versions {file-id: file-id, version: version}) ERR-FILE-NOT-FOUND))
    )
  )
)

;; Get the latest version information
(define-read-only (get-latest-version (file-id (string-ascii 64)))
  (begin
    ;; Validate file-id
    (asserts! (is-valid-string-ascii file-id) ERR-EMPTY-STRING)
    
    (let 
      (
        (file-data (unwrap! (map-get? files {file-id: file-id}) ERR-FILE-NOT-FOUND))
        (permissions (default-to {can-edit: false, can-view: false} 
                      (map-get? file-editors {file-id: file-id, editor: tx-sender})))
      )
      ;; For private files, only allow access to owner or users with permission
      (asserts! (or 
                 (not (get is-private file-data))
                 (is-eq tx-sender (get owner file-data))
                 (get can-view permissions))
                ERR-NOT-AUTHORIZED)
      
      (ok (unwrap! 
            (map-get? file-versions 
                      {file-id: file-id, version: (get current-version file-data)}) 
            ERR-FILE-NOT-FOUND))
    )
  )
)

;; Change file privacy settings
(define-public (set-privacy (file-id (string-ascii 64)) (is-private bool))
  (begin
    ;; Validate file-id
    (asserts! (is-valid-string-ascii file-id) ERR-EMPTY-STRING)
    
    (let 
      (
        (file-data (unwrap! (map-get? files {file-id: file-id}) ERR-FILE-NOT-FOUND))
      )
      ;; Only owner can change privacy settings
      (asserts! (is-eq tx-sender (get owner file-data)) ERR-NOT-FILE-OWNER)
      
      ;; Update privacy setting
      (map-set files
        {file-id: file-id}
        (merge file-data { is-private: is-private })
      )
      
      (ok true)
    )
  )
)

;; Grant permissions to another user
(define-public (grant-permissions (file-id (string-ascii 64)) 
                                 (editor principal)
                                 (can-edit bool)
                                 (can-view bool))
  (begin
    ;; Validate file-id
    (asserts! (is-valid-string-ascii file-id) ERR-EMPTY-STRING)
    
    (let 
      (
        (file-data (unwrap! (map-get? files {file-id: file-id}) ERR-FILE-NOT-FOUND))
      )
      ;; Only owner can grant permissions
      (asserts! (is-eq tx-sender (get owner file-data)) ERR-NOT-FILE-OWNER)
      
      ;; Set permissions
      (map-set file-editors
        {file-id: file-id, editor: editor}
        {can-edit: can-edit, can-view: can-view}
      )
      
      (ok true)
    )
  )
)

;; Revoke permissions
(define-public (revoke-permissions (file-id (string-ascii 64)) (editor principal))
  (begin
    ;; Validate file-id
    (asserts! (is-valid-string-ascii file-id) ERR-EMPTY-STRING)
    
    (let 
      (
        (file-data (unwrap! (map-get? files {file-id: file-id}) ERR-FILE-NOT-FOUND))
      )
      ;; Only owner can revoke permissions
      (asserts! (is-eq tx-sender (get owner file-data)) ERR-NOT-FILE-OWNER)
      
      ;; Delete permissions entry
      (map-delete file-editors {file-id: file-id, editor: editor})
      
      (ok true)
    )
  )
)

;; Check if user has permissions
(define-read-only (check-permissions (file-id (string-ascii 64)) (user principal))
  (begin
    ;; Validate file-id
    (asserts! (is-valid-string-ascii file-id) ERR-EMPTY-STRING)
    
    (let 
      (
        (file-data (unwrap! (map-get? files {file-id: file-id}) ERR-FILE-NOT-FOUND))
        (permissions (default-to {can-edit: false, can-view: false} 
                      (map-get? file-editors {file-id: file-id, editor: user})))
      )
      ;; If user is owner, they have full permissions
      (if (is-eq user (get owner file-data))
        (ok {can-edit: true, can-view: true})
        (ok permissions)
      )
    )
  )
)

;; Transfer file ownership
(define-public (transfer-ownership (file-id (string-ascii 64)) (new-owner principal))
  (begin
    ;; Validate file-id
    (asserts! (is-valid-string-ascii file-id) ERR-EMPTY-STRING)
    
    (let 
      (
        (file-data (unwrap! (map-get? files {file-id: file-id}) ERR-FILE-NOT-FOUND))
      )
      ;; Only owner can transfer
      (asserts! (is-eq tx-sender (get owner file-data)) ERR-NOT-FILE-OWNER)
      
      ;; Update owner
      (map-set files
        {file-id: file-id}
        (merge file-data { owner: new-owner })
      )
      
      ;; Add new owner as editor with full permissions
      (map-set file-editors
        {file-id: file-id, editor: new-owner}
        {can-edit: true, can-view: true}
      )
      
      (ok true)
    )
  )
)

;; List all versions of a file
(define-read-only (list-versions (file-id (string-ascii 64)))
  (begin
    ;; Validate file-id
    (asserts! (is-valid-string-ascii file-id) ERR-EMPTY-STRING)
    
    (let 
      (
        (file-data (unwrap! (map-get? files {file-id: file-id}) ERR-FILE-NOT-FOUND))
        (permissions (default-to {can-edit: false, can-view: false} 
                      (map-get? file-editors {file-id: file-id, editor: tx-sender})))
        (total-versions (get current-version file-data))
      )
      ;; For private files, only allow access to owner or users with permission
      (asserts! (or 
                 (not (get is-private file-data))
                 (is-eq tx-sender (get owner file-data))
                 (get can-view permissions))
                ERR-NOT-AUTHORIZED)
      
      (ok total-versions)
    )
  )
)

;; Delete file (only owner can call)
(define-public (delete-file (file-id (string-ascii 64)))
  (begin
    ;; Validate file-id
    (asserts! (is-valid-string-ascii file-id) ERR-EMPTY-STRING)
    
    (let 
      (
        (file-data (unwrap! (map-get? files {file-id: file-id}) ERR-FILE-NOT-FOUND))
        (current-version (get current-version file-data))
      )
      ;; Only owner can delete
      (asserts! (is-eq tx-sender (get owner file-data)) ERR-NOT-FILE-OWNER)
      
      ;; Delete file metadata
      (map-delete files {file-id: file-id})
      
      ;; Delete versions inline
      (begin
        (if (>= current-version u1) (map-delete file-versions {file-id: file-id, version: u1}) true)
        (if (>= current-version u2) (map-delete file-versions {file-id: file-id, version: u2}) true)
        (if (>= current-version u3) (map-delete file-versions {file-id: file-id, version: u3}) true)
        (if (>= current-version u4) (map-delete file-versions {file-id: file-id, version: u4}) true)
        (if (>= current-version u5) (map-delete file-versions {file-id: file-id, version: u5}) true)
        (if (>= current-version u6) (map-delete file-versions {file-id: file-id, version: u6}) true)
        (if (>= current-version u7) (map-delete file-versions {file-id: file-id, version: u7}) true)
        (if (>= current-version u8) (map-delete file-versions {file-id: file-id, version: u8}) true)
        (if (>= current-version u9) (map-delete file-versions {file-id: file-id, version: u9}) true)
        (if (>= current-version u10) (map-delete file-versions {file-id: file-id, version: u10}) true)
      )
      
      (ok true)
    )
  )
)

;; Update contract owner (only current owner can call)
(define-public (update-contract-owner (new-owner principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (var-set contract-owner new-owner)
    (ok true)
  )
)