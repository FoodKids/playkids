using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;
using UnityEngine.Video;
using UnityEngine.SceneManagement;

public class LunchTimeManager : MonoBehaviour {

    public Button button;
    public Image imageCover;
    public VideoPlayer videoPlayer;

	// Use this for initialization
	void Start () {
        this.button.gameObject.SetActive(false);
        StartCoroutine(ShowButton());		
	}
	
    IEnumerator ShowButton() {
        yield return new WaitForSeconds(8);
        this.button.gameObject.SetActive(true);
    }

    public void ButtonPressed() {
        this.videoPlayer.Pause();
        this.imageCover.color = new Color(0, 0, 0, 255.0f);
        StartCoroutine(LoadAR());       
    }

    IEnumerator LoadAR()
    {
        AsyncOperation asyncLoad = SceneManager.LoadSceneAsync(1);
        while (!asyncLoad.isDone)
        {
            yield return null;
        }
    }
}
