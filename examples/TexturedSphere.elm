module TexturedSphere exposing (main)

import Angle exposing (Angle)
import Axis3d exposing (Axis3d)
import Browser
import Browser.Events
import Camera3d exposing (Camera3d)
import Color exposing (Color)
import Direction3d
import Frame3d exposing (Frame3d)
import Html exposing (Html)
import Illuminance
import Json.Decode as Decode exposing (Decoder)
import Length exposing (Meters)
import Luminance
import LuminousFlux
import Palette.Tango as Tango
import Parameter1d
import Pixels
import Point3d
import Quantity
import Scene3d
import Scene3d.Chromaticity as Chromaticity
import Scene3d.Exposure as Exposure
import Scene3d.Material as Material exposing (Material)
import Sphere3d
import Task
import Temperature
import Vector3d exposing (Vector3d)
import Viewpoint3d exposing (Viewpoint3d)
import WebGL.Texture


type SphereCoordinates
    = SphereCoordinates


type WorldCoordinates
    = WorldCoordinates


type Model
    = Loading
        { colorTexture : Maybe (Material.Texture Color)
        , roughnessTexture : Maybe (Material.Texture Float)
        , metallicTexture : Maybe (Material.Texture Float)
        }
    | Loaded
        { colorTexture : Material.Texture Color
        , roughnessTexture : Material.Texture Float
        , metallicTexture : Material.Texture Float
        , sphereFrame : Frame3d Meters WorldCoordinates { defines : SphereCoordinates }
        , orbiting : Bool
        }
    | Errored String


type Msg
    = GotColorTexture (Result WebGL.Texture.Error (Material.Texture Color))
    | GotRoughnessTexture (Result WebGL.Texture.Error (Material.Texture Float))
    | GotMetallicTexture (Result WebGL.Texture.Error (Material.Texture Float))
    | MouseDown
    | MouseUp
    | MouseMove Float Float


init : ( Model, Cmd Msg )
init =
    ( Loading
        { colorTexture = Nothing
        , roughnessTexture = Nothing
        , metallicTexture = Nothing
        }
    , Cmd.batch
        [ Material.load "https://ianmackenzie.github.io/elm-3d-scene/examples/metal/Metal03_col.jpg"
            |> Task.attempt GotColorTexture
        , Material.load "https://ianmackenzie.github.io/elm-3d-scene/examples/metal/Metal03_rgh.jpg"
            |> Task.attempt GotRoughnessTexture
        , Material.load "https://ianmackenzie.github.io/elm-3d-scene/examples/metal/Metal03_met.jpg"
            |> Task.attempt GotMetallicTexture
        ]
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update message model =
    let
        updatedModel =
            case model of
                Loading textures ->
                    case message of
                        GotColorTexture (Ok colorTexture) ->
                            checkIfLoaded { textures | colorTexture = Just colorTexture }

                        GotRoughnessTexture (Ok roughnessTexture) ->
                            checkIfLoaded { textures | roughnessTexture = Just roughnessTexture }

                        GotMetallicTexture (Ok metallicTexture) ->
                            checkIfLoaded { textures | metallicTexture = Just metallicTexture }

                        GotColorTexture (Err error) ->
                            Errored "Error loading color texture"

                        GotRoughnessTexture (Err error) ->
                            Errored "Error loading roughness texture"

                        GotMetallicTexture (Err error) ->
                            Errored "Error loading metallic texture"

                        MouseDown ->
                            model

                        MouseUp ->
                            model

                        MouseMove _ _ ->
                            model

                Loaded loadedModel ->
                    case message of
                        GotColorTexture _ ->
                            model

                        GotRoughnessTexture _ ->
                            model

                        GotMetallicTexture _ ->
                            model

                        MouseDown ->
                            Loaded { loadedModel | orbiting = True }

                        MouseUp ->
                            Loaded { loadedModel | orbiting = False }

                        MouseMove dx dy ->
                            if loadedModel.orbiting then
                                let
                                    rotationVector =
                                        Vector3d.withLength (Angle.degrees dx)
                                            (Viewpoint3d.yDirection viewpoint)
                                            |> Vector3d.plus
                                                (Vector3d.withLength (Angle.degrees dy)
                                                    (Viewpoint3d.xDirection viewpoint)
                                                )
                                in
                                case Vector3d.direction rotationVector of
                                    Just direction ->
                                        let
                                            newFrame =
                                                loadedModel.sphereFrame
                                                    |> Frame3d.rotateAround
                                                        (Axis3d.through (Frame3d.originPoint loadedModel.sphereFrame) direction)
                                                        (Vector3d.length rotationVector)
                                        in
                                        Loaded { loadedModel | sphereFrame = newFrame }

                                    Nothing ->
                                        model

                            else
                                model

                Errored _ ->
                    model
    in
    ( updatedModel, Cmd.none )


checkIfLoaded :
    { colorTexture : Maybe (Material.Texture Color)
    , roughnessTexture : Maybe (Material.Texture Float)
    , metallicTexture : Maybe (Material.Texture Float)
    }
    -> Model
checkIfLoaded textures =
    case ( textures.colorTexture, textures.roughnessTexture, textures.metallicTexture ) of
        ( Just colorTexture, Just roughnessTexture, Just metallicTexture ) ->
            Loaded
                { colorTexture = colorTexture
                , roughnessTexture = roughnessTexture
                , metallicTexture = metallicTexture
                , sphereFrame = Frame3d.atOrigin
                , orbiting = False
                }

        _ ->
            Loading textures


viewpoint : Viewpoint3d Meters WorldCoordinates
viewpoint =
    Viewpoint3d.lookAt
        { focalPoint = Point3d.origin
        , eyePoint = Point3d.centimeters 20 10 10
        , upDirection = Direction3d.positiveZ
        }


sunlight =
    Scene3d.directionalLight Scene3d.doesNotCastShadows
        { chromaticity = Chromaticity.sunlight
        , intensity = Illuminance.lux 20000
        , direction = Direction3d.yz (Angle.degrees -120)
        }


camera : Camera3d Meters WorldCoordinates
camera =
    Camera3d.perspective
        { viewpoint = viewpoint
        , verticalFieldOfView = Angle.degrees 30
        }


view : Model -> Html msg
view model =
    case model of
        Loaded { colorTexture, roughnessTexture, metallicTexture, sphereFrame } ->
            let
                material =
                    Material.texturedPbr
                        { baseColor = colorTexture
                        , roughness = roughnessTexture
                        , metallic = metallicTexture
                        }
            in
            Scene3d.toHtml [ Scene3d.dynamicRange 2 ]
                { camera = camera
                , clipDepth = Length.centimeters 0.5
                , dimensions = ( Pixels.pixels 800, Pixels.pixels 600 )
                , environmentalLighting =
                    Scene3d.softLighting
                        { upDirection = Direction3d.positiveZ
                        , above = ( Luminance.nits 3000, Chromaticity.d65 )
                        , below = ( Luminance.nits 300, Chromaticity.d65 )
                        }
                , lights =
                    Scene3d.oneLight sunlight
                , exposure = Exposure.fromEv100 11
                , whiteBalance = Scene3d.defaultWhiteBalance
                , background = Scene3d.transparentBackground
                }
                [ Sphere3d.withRadius (Length.centimeters 5) Point3d.origin
                    |> Scene3d.sphere Scene3d.doesNotCastShadows material
                    |> Scene3d.placeIn sphereFrame
                ]

        Loading _ ->
            Html.text "Loading..."

        Errored message ->
            Html.text message


decodeMouseMove : Decoder Msg
decodeMouseMove =
    Decode.map2 MouseMove
        (Decode.field "movementX" Decode.float)
        (Decode.field "movementY" Decode.float)


subscriptions : Model -> Sub Msg
subscriptions model =
    case model of
        Loading _ ->
            Sub.none

        Errored _ ->
            Sub.none

        Loaded { orbiting } ->
            if orbiting then
                Sub.batch
                    [ Browser.Events.onMouseMove decodeMouseMove
                    , Browser.Events.onMouseUp (Decode.succeed MouseUp)
                    ]

            else
                Browser.Events.onMouseDown (Decode.succeed MouseDown)


main : Program () Model Msg
main =
    Browser.element
        { init = always init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
